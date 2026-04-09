#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BASENAME="$(basename "$PROJECT_DIR")"
VENV_DIR="${VENV_DIR:-$HOME/venv/$BASENAME}"
COMFYUI_DIR="${COMFYUI_DIR:-$PROJECT_DIR/vendor/ComfyUI}"
ENV_FILE="${ENV_FILE:-$PROJECT_DIR/.env}"
IP="${1:-${HOST:-0.0.0.0}}"
PORT="${2:-${PORT:-8188}}"

if [ ! -d "$VENV_DIR" ]; then
  echo "missing venv: $VENV_DIR (run ./install.sh first)" >&2
  return 1 2>/dev/null || exit 1
fi

if [ ! -f "$COMFYUI_DIR/main.py" ]; then
  echo "missing ComfyUI checkout: $COMFYUI_DIR (run ./install.sh first)" >&2
  return 1 2>/dev/null || exit 1
fi

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

mkdir -p \
  "${COMFYUI_INPUT_DIR:-$PROJECT_DIR/input}" \
  "${COMFYUI_OUTPUT_DIR:-$PROJECT_DIR/output}" \
  "${COMFYUI_TEMP_DIR:-$PROJECT_DIR/tmp}" \
  "${HF_HOME:-$PROJECT_DIR/.cache/huggingface}" \
  "${TORCH_HOME:-$PROJECT_DIR/.cache/torch}"

export HF_HOME="${HF_HOME:-$PROJECT_DIR/.cache/huggingface}"
export TORCH_HOME="${TORCH_HOME:-$PROJECT_DIR/.cache/torch}"
export PYTORCH_CUDA_ALLOC_CONF="${PYTORCH_CUDA_ALLOC_CONF:-expandable_segments:True}"
export CUDA_DEVICE_ORDER="${CUDA_DEVICE_ORDER:-PCI_BUS_ID}"
export NVIDIA_VISIBLE_DEVICES="${NVIDIA_VISIBLE_DEVICES:-all}"

EXTRA_ARGS=()
[ -n "${COMFYUI_EXTRA_ARGS:-}" ] && read -r -a EXTRA_ARGS <<<"$COMFYUI_EXTRA_ARGS"

cd "$COMFYUI_DIR"
exec python main.py \
  --listen "$IP" \
  --port "$PORT" \
  --input-directory "${COMFYUI_INPUT_DIR:-$PROJECT_DIR/input}" \
  --output-directory "${COMFYUI_OUTPUT_DIR:-$PROJECT_DIR/output}" \
  --temp-directory "${COMFYUI_TEMP_DIR:-$PROJECT_DIR/tmp}" \
  "${EXTRA_ARGS[@]}"
