# LOTULIS photo-editing worker for Runpod Serverless.
#
# Base: Runpod's official ComfyUI worker (handler + ComfyUI, no models).
# Adds:
#   - ComfyUI-RMBG: text-prompted segmentation ("sky", "trash can") via GroundingDINO + SAM,
#     so an edit can be limited to one region and the rest of the photo is kept pixel-exact.
#   - ComfyUI-Inpaint-CropAndStitch: edit a crop at native resolution, paste it back.
#   - The segmentation weights baked in, so cold starts do not download them.
#
# The big diffusion weights (Qwen-Image-Edit-2509, text encoder, VAE, Lightning LoRA)
# stay on the network volume at /runpod-volume/models/... (see assistant/runpod/README.md).

FROM runpod/worker-comfyui:5.10.0-base

# opencv-python (pulled in by ComfyUI-RMBG) needs these shared libraries at import time.
RUN apt-get update && apt-get install -y --no-install-recommends libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Custom node packs, by their Comfy Registry ids. The helper also installs each
# pack's requirements.txt.
RUN comfy-node-install comfyui-rmbg comfyui-inpaint-cropandstitch

# Segmentation weights, in the folders ComfyUI-RMBG's SegmentV2 node reads from
# (models/grounding-dino and models/SAM under the ComfyUI install).
RUN comfy model download --url https://huggingface.co/1038lab/GroundingDINO/resolve/main/GroundingDINO_SwinT_OGC.cfg.py \
        --relative-path models/grounding-dino --filename GroundingDINO_SwinT_OGC.cfg.py \
    && comfy model download --url https://huggingface.co/1038lab/GroundingDINO/resolve/main/groundingdino_swint_ogc.pth \
        --relative-path models/grounding-dino --filename groundingdino_swint_ogc.pth \
    && comfy model download --url https://huggingface.co/1038lab/sam/resolve/main/sam_hq_vit_h.pth \
        --relative-path models/SAM --filename sam_hq_vit_h.pth

# Quieter logs than the base image's DEBUG default.
ENV COMFY_LOG_LEVEL=INFO
