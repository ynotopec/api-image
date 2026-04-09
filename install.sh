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

ensure_comfyui_api_key() {
  [ -f "$ENV_FILE" ] || return 0
  log "ensuring COMFYUI_API_KEY exists in .env"
  python3 - "$ENV_FILE" <<'PY'
import pathlib
import re
import secrets
import sys

env_path = pathlib.Path(sys.argv[1])
text = env_path.read_text(encoding="utf-8")

line_re = re.compile(r'^(COMFYUI_API_KEY=)(.*)$', re.MULTILINE)
m = line_re.search(text)
if m:
    raw_val = m.group(2).strip()
    cleaned = raw_val.strip('"').strip("'")
    if cleaned:
        print("[install] COMFYUI_API_KEY already set in .env")
        raise SystemExit(0)
    token = secrets.token_urlsafe(32)
    text = text[:m.start()] + f'COMFYUI_API_KEY="{token}"' + text[m.end():]
    env_path.write_text(text, encoding="utf-8")
    print("[install] generated COMFYUI_API_KEY in .env")
else:
    token = secrets.token_urlsafe(32)
    suffix = "" if text.endswith("\n") else "\n"
    text = text + suffix + f'COMFYUI_API_KEY="{token}"\n'
    env_path.write_text(text, encoding="utf-8")
    print("[install] appended COMFYUI_API_KEY in .env")
PY
}

bootstrap_workflow_json() {
  local workflow_dir workflow_repo_url workflow_repo_ref workflow_json_path workflow_clone_dir
  workflow_dir="$PROJECT_DIR/workflows"
  workflow_repo_url="${WORKFLOW_REPO_URL:-}"
  workflow_repo_ref="${WORKFLOW_REPO_REF:-main}"
  workflow_json_path="${WORKFLOW_JSON_PATH:-}"

  mkdir -p "$workflow_dir"

  if [ ! -f "$workflow_dir/optimum-image-edit.api.json" ]; then
    cat > "$workflow_dir/optimum-image-edit.api.json" <<'JSON'
{
  "note": "Starter template only. Replace with your real ComfyUI API-exported workflow JSON.",
  "required_for_openwebui_editing": true,
  "expected_mapping": {
    "prompt_input": "Set in OpenWebUI workflow mapping",
    "image_input": "Set in OpenWebUI workflow mapping",
    "image_output": "Set in OpenWebUI workflow mapping"
  }
}
JSON
    log "created starter workflow JSON: workflows/optimum-image-edit.api.json"
  fi

  if [ -z "$workflow_repo_url" ]; then
    return 0
  fi

  mkdir -p "$PROJECT_DIR/tmp"
  workflow_clone_dir="$(mktemp -d "$PROJECT_DIR/tmp/workflow-repo.XXXXXX")"
  trap 'rm -rf "$workflow_clone_dir"' RETURN

  log "syncing workflow git repo: $workflow_repo_url (ref: $workflow_repo_ref)"
  git clone --depth 1 --branch "$workflow_repo_ref" "$workflow_repo_url" "$workflow_clone_dir"

  if [ -n "$workflow_json_path" ]; then
    if [ ! -f "$workflow_clone_dir/$workflow_json_path" ]; then
      echo "workflow json not found in repo: $workflow_json_path" >&2
      exit 1
    fi
    cp "$workflow_clone_dir/$workflow_json_path" "$workflow_dir/$(basename "$workflow_json_path")"
    log "copied workflow JSON from repo: $workflow_json_path"
  else
    if compgen -G "$workflow_clone_dir/*.json" >/dev/null; then
      cp "$workflow_clone_dir"/*.json "$workflow_dir/"
      log "copied workflow JSON files from repo root into workflows/"
    elif compgen -G "$workflow_clone_dir/workflows/*.json" >/dev/null; then
      cp "$workflow_clone_dir"/workflows/*.json "$workflow_dir/"
      log "copied workflow JSON files from repo workflows/ into local workflows/"
    else
      log "no workflow JSON files found in workflow repo; keeping local starter template"
    fi
  fi
}

ensure_comfyui_api_key
bootstrap_workflow_json

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
