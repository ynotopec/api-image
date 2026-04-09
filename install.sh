#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BASENAME="$(basename "$PROJECT_DIR")"
VENV_DIR="${VENV_DIR:-$HOME/venv/$BASENAME}"
COMFYUI_DIR="${COMFYUI_DIR:-$PROJECT_DIR/vendor/ComfyUI}"
ENV_FILE="${ENV_FILE:-$PROJECT_DIR/.env}"

log() { printf '[install] %s\n' "$*"; }
need() { command -v "$1" >/dev/null 2>&1 || { echo "missing required command: $1" >&2; exit 1; }; }

need git
need python3
need curl

if ! command -v uv >/dev/null 2>&1; then
  log "installing uv"
  curl -fsSL https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi

mkdir -p "$(dirname "$VENV_DIR")"
if [ ! -d "$VENV_DIR" ]; then
  log "creating venv: $VENV_DIR"
  uv venv "$VENV_DIR"
else
  log "venv already present: $VENV_DIR"
fi

# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

log "upgrading base tooling"
uv pip install --upgrade pip setuptools wheel

mkdir -p "$PROJECT_DIR/vendor"
if [ ! -d "$COMFYUI_DIR/.git" ]; then
  log "cloning ComfyUI"
  git clone https://github.com/comfy-org/ComfyUI.git "$COMFYUI_DIR"
else
  log "updating ComfyUI"
  git -C "$COMFYUI_DIR" fetch --tags --prune
  current_branch="$(git -C "$COMFYUI_DIR" rev-parse --abbrev-ref HEAD || true)"
  if [ -n "$current_branch" ] && [ "$current_branch" != "HEAD" ]; then
    git -C "$COMFYUI_DIR" pull --ff-only origin "$current_branch"
  else
    log "detached HEAD detected in vendor/ComfyUI, skipping git pull"
  fi
fi

if [ -f "$PROJECT_DIR/requirements.lock.txt" ]; then
  log "installing pinned helper dependencies"
  uv pip install -r "$PROJECT_DIR/requirements.lock.txt"
fi

install_torch_default() {
  local arch os
  arch="$(uname -m)"
  os="$(uname -s)"

  if python - <<'PY' >/dev/null 2>&1
import torch
print(torch.__version__)
PY
  then
    log "torch already available in venv"
    return 0
  fi

  if [ -n "${TORCH_WHL:-}" ]; then
    log "installing torch from TORCH_WHL"
    uv pip install "$TORCH_WHL"
    return 0
  fi

  if [ -n "${TORCH_PACKAGES:-}" ]; then
    log "installing torch from TORCH_PACKAGES"
    if [ -n "${TORCH_INDEX_URL:-}" ]; then
      # shellcheck disable=SC2086
      uv pip install --index-url "$TORCH_INDEX_URL" $TORCH_PACKAGES
    else
      # shellcheck disable=SC2086
      uv pip install $TORCH_PACKAGES
    fi
    return 0
  fi

  case "$os/$arch" in
    Linux/x86_64)
      log "installing default CUDA PyTorch wheels for Linux x86_64"
      uv pip install --index-url https://download.pytorch.org/whl/cu128 torch torchvision torchaudio
      ;;
    Linux/aarch64)
      log "Linux aarch64 detected: trying generic PyTorch first"
      if ! uv pip install torch torchvision torchaudio; then
        cat >&2 <<'MSG'
Could not auto-install torch on aarch64.
Set one of these and rerun:
  TORCH_PACKAGES="torch torchvision torchaudio"
  TORCH_INDEX_URL="<your torch wheel index>"
  TORCH_WHL="<direct wheel url>"
MSG
        exit 1
      fi
      ;;
    *)
      log "non-default platform detected: trying generic PyTorch"
      uv pip install torch torchvision torchaudio
      ;;
  esac
}

install_torch_default

log "installing ComfyUI requirements"
uv pip install -r "$COMFYUI_DIR/requirements.txt"

mkdir -p "$PROJECT_DIR/models" "$PROJECT_DIR/input" "$PROJECT_DIR/output" "$PROJECT_DIR/tmp"

if [ ! -f "$ENV_FILE" ] && [ -f "$PROJECT_DIR/.env.example" ]; then
  log "creating .env from .env.example"
  cp "$PROJECT_DIR/.env.example" "$ENV_FILE"
fi

log "validating torch/cuda"
python - <<'PY'
import os
try:
    import torch
    print(f"[install] torch={torch.__version__}")
    print(f"[install] cuda_available={torch.cuda.is_available()}")
    if torch.cuda.is_available():
        print(f"[install] cuda_device_count={torch.cuda.device_count()}")
        print(f"[install] cuda_device_0={torch.cuda.get_device_name(0)}")
except Exception as e:
    print(f"[install] torch validation warning: {e}")
PY

log "done"
