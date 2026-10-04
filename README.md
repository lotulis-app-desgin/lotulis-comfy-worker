# lotulis-comfy-worker

Docker image for the LOTULIS photo-editing endpoint on Runpod Serverless.

It is Runpod's official ComfyUI worker plus:

- **ComfyUI-RMBG** for text-prompted masks ("sky", "the trash can") with GroundingDINO + SAM.
- **ComfyUI-Inpaint-CropAndStitch** for editing a crop at native resolution and pasting it back.
- GroundingDINO SwinT and SAM-HQ ViT-H weights baked in.

The diffusion weights (Qwen-Image-Edit-2509 fp8, Qwen2.5-VL text encoder, Qwen VAE,
Lightning LoRA) are **not** in the image. They live on the Runpod network volume, mounted at
`/runpod-volume/models/...`.

## Build

Every push to `main` builds `linux/amd64` on GitHub Actions and pushes

```
ghcr.io/lotulis-app-desgin/lotulis-comfy-worker:latest
ghcr.io/lotulis-app-desgin/lotulis-comfy-worker:<short-sha>
```

## Deploy

Point the Runpod serverless template at the image (see `assistant/runpod/README.md` for the
endpoint, volume and template ids):

```
runpodctl template create --name lotulis-comfy-worker --serverless \
  --image ghcr.io/lotulis-app-desgin/lotulis-comfy-worker:<short-sha> --container-disk-in-gb 25
runpodctl serverless update <endpoint-id> --template-id <new-template-id>
```

Pin the sha tag on the template, never `latest`, so a rebuild cannot change production.

## Workflows and client

The ComfyUI API workflows and the test client live in the assistant project under `runpod/`.
