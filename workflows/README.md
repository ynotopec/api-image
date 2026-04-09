Put your exported ComfyUI workflow JSON files here.

For OpenWebUI compatibility:
- export the workflow in API format
- map prompt / image input / output nodes correctly in OpenWebUI
- keep one JSON per workflow variant for easier maintenance

For image editing in OpenWebUI, this API-format workflow JSON is required.
(`ComfyUI API Key` is separate and only controls authentication.)

Installer behavior:
- `install.sh` creates `optimum-image-edit.api.json` as a starter template when missing.
- If `WORKFLOW_REPO_URL` is set in `.env`, `install.sh` can pull workflow JSON files from git.
- The git clone is temporary and removed after copy, so `workflows/` only keeps JSON files.

Suggested naming:
- flux-text2img.api.json
- flux-edit.api.json
- flux2-edit.api.json
- qwen-image-edit.api.json
