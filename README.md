# openwebui-comfyui-flux2-editor

Idempotent ComfyUI wrapper project for OpenWebUI image generation / image editing workflows (including FLUX-family editors) with:

- `uv`
- `~/venv/<basename project dir>`
- `install.sh` upgrade-safe
- `source run.sh [IP] [PORT]`
- `.env.example`
- `README.md`
- Linux / GPU-first layout for H100 and DGX Spark style environments

## What this repo does

This repo installs and runs **ComfyUI** in a project-owned layout so OpenWebUI can connect to it.

OpenWebUI compatibility relies on:

1. running ComfyUI through `source run.sh [IP] [PORT]`
2. exporting the ComfyUI workflow in **API format**
3. importing that workflow in OpenWebUI image generation / editing settings
4. if enabled, using the same ComfyUI API key in both ComfyUI and OpenWebUI

`install.sh` now helps bootstrap both:
- API key generation in `.env` (if empty)
- a starter workflow JSON in `workflows/`
- optional workflow JSON sync from a git repository

`run.sh` is responsible for the network bind. You should not need to pass raw ComfyUI network flags manually.

## Tree

```text
openwebui-comfyui-flux2-editor/
├── .env.example
├── .gitignore
├── install.sh
├── README.md
├── requirements.lock.txt
├── run.sh
├── vendor/
│   └── ComfyUI/
├── input/
├── output/
├── tmp/
└── workflows/
    └── README.md
```

## Quick start

```bash
git clone <your-repo-url> openwebui-comfyui-flux2-editor
cd openwebui-comfyui-flux2-editor
./install.sh
cp -n .env.example .env
source run.sh 0.0.0.0 8188
```

Then open:

```text
http://<server-ip>:8188
```

## Runtime behavior

Examples:

```bash
source run.sh
source run.sh 127.0.0.1 8188
source run.sh 0.0.0.0 8188
source run.sh 192.168.1.50 8188
```

Meaning:

- `source run.sh` → uses `.env` or built-in defaults
- `source run.sh 127.0.0.1 8188` → local-only bind
- `source run.sh 0.0.0.0 8188` → all interfaces
- `source run.sh <specific-ip> <port>` → bind to one interface only

## OpenWebUI hookup

In OpenWebUI, configure ComfyUI as image backend and point it to:

```text
http://<your-comfyui-ip>:8188
```

For **image editing**, your ComfyUI workflow must be exported in **API format** and mapped correctly in OpenWebUI.

### ComfyUI API key (optional but recommended)

You can protect ComfyUI API access with an API key:

1. Set `COMFYUI_API_KEY` in `.env`.
2. Start ComfyUI with `source run.sh ...` (the script passes `--api-key` automatically when this variable is set).
3. In OpenWebUI ComfyUI connection settings, set **ComfyUI API Key** to the same value.

If the key is set only on one side, requests will fail with authorization errors.
If `COMFYUI_API_KEY` is empty, `./install.sh` generates one automatically in `.env`.

## Workflow notes for FLUX / FLUX.2 editors

This project is intentionally **workflow-agnostic**.

Use it with any ComfyUI workflow that supports:

- one text prompt input
- optionally one image input
- one image output

Typical use cases:

- FLUX text-to-image
- FLUX Kontext / image-edit style workflows
- FLUX-family distilled or custom edit workflows
- Qwen image edit workflows

Put your exported OpenWebUI-compatible API JSON files under `workflows/`.

Do you need a workflow JSON for image edit?

- **Yes** for OpenWebUI image editing via ComfyUI.
- OpenWebUI needs a ComfyUI **API-format workflow JSON** to know which node receives:
  - prompt text,
  - input image (for edit/inpaint/img2img flows),
  - and which node returns the output image.
- API key and workflow JSON solve different problems:
  - API key = authentication/security
  - workflow JSON = execution graph/mapping

### Workflow JSON bootstrap (local or git)

`./install.sh` will always ensure a starter file exists:

- `workflows/optimum-image-edit.api.json` (template starter, not a real graph)

To pull real workflow JSON from git during install, set in `.env` before running:

```bash
WORKFLOW_REPO_URL="https://github.com/<owner>/<repo>.git"
WORKFLOW_REPO_REF="main"                  # optional, defaults to main
WORKFLOW_JSON_PATH="workflows/flux2-edit.api.json"  # optional
```

Behavior:
- If `WORKFLOW_JSON_PATH` is set, that exact JSON file is copied into local `workflows/`.
- If not set, installer tries to copy `*.json` from repo root, then `repo/workflows/`.
- The workflow repo clone is temporary (under `tmp/`) and removed automatically; only JSON outputs are kept in `workflows/`.

## Upgrade

Safe to rerun anytime:

```bash
./install.sh
```

What it updates:

- local `uv` environment dependencies
- `vendor/ComfyUI` checkout (fast-forward pull when possible)
- project bootstrap directories

## H100 / DGX Spark notes

### H100 / Linux x86_64

Default install path tries:

```bash
uv pip install --index-url https://download.pytorch.org/whl/cu128 torch torchvision torchaudio
```

If you need another stack:

```bash
export TORCH_INDEX_URL='https://download.pytorch.org/whl/cu128'
export TORCH_PACKAGES='torch torchvision torchaudio'
./install.sh
```

### DGX Spark / Linux aarch64

`install.sh` tries a generic PyTorch install first.
If your platform requires vendor-specific wheels, set one of:

```bash
export TORCH_PACKAGES='torch torchvision torchaudio'
export TORCH_INDEX_URL='<your wheel index>'
# or
export TORCH_WHL='<direct wheel url>'
./install.sh
```

If torch is already present and importable in the project venv, `install.sh` reuses it.

## systemd example

Because `run.sh` is sourceable, interactive use is:

```bash
source /opt/openwebui-comfyui-flux2-editor/run.sh 0.0.0.0 8188
```

For systemd, call it through bash:

```ini
[Unit]
Description=ComfyUI for OpenWebUI
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/openwebui-comfyui-flux2-editor
EnvironmentFile=/opt/openwebui-comfyui-flux2-editor/.env
ExecStart=/usr/bin/bash -lc 'source /opt/openwebui-comfyui-flux2-editor/run.sh 0.0.0.0 8188'
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

## Common files

### `.env`

Copy from example:

```bash
cp -n .env.example .env
```

### `workflows/`

Store exported ComfyUI API-format workflows there.

## Notes

- `vendor/ComfyUI` is managed by this repo
- `input/`, `output/`, `tmp/` are project-local
- `HF_HOME` and `TORCH_HOME` are also project-local by default
