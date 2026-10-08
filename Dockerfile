# LOTULIS photo-editing worker for Runpod Serverless.
#
# Base: Runpod's official ComfyUI worker (handler + ComfyUI, no models).
# Adds:
#   - ComfyUI-RMBG: text-prompted segmentation ("sky", "trash can") via GroundingDINO + SAM,
#     so an edit can be limited to one region and the rest of the photo is kept pixel-exact.
#   - ComfyUI-Inpaint-CropAndStitch: edit a crop at native resolution, paste it back.
#   - The segmentation weights baked in, so cold starts do not download them.
#   - ComfyUI-VAE-Utils + the Wan2.1 2x VAE (2x decode) and the 2511 Lightning LoRA, baked in.
#
# The big diffusion weights (Qwen-Image-Edit-2509, text encoder, VAE, Lightning LoRA)
# stay on the network volume at /runpod-volume/models/... (see assistant/runpod/README.md).

FROM runpod/worker-comfyui:5.10.0-base

# opencv-python (pulled in by ComfyUI-RMBG) needs these shared libraries at import time.
RUN apt-get update && apt-get install -y --no-install-recommends libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Custom node packs, by their Comfy Registry ids.
#
# Gotcha (worker-comfyui issue #237): comfy-node-install puts each pack's pip
# requirements into /comfyui/.venv, but the worker launches ComfyUI from
# /opt/venv, so the packs fail to import at boot and every node is "missing".
# Install the requirements into /opt/venv ourselves, the same way the base
# image does for its own pre-installed packs.
RUN comfy-node-install comfyui-rmbg comfyui-inpaint-cropandstitch \
    && for r in /comfyui/custom_nodes/*/requirements.txt; do \
         [ -f "$r" ] && uv pip install --python /opt/venv/bin/python -r "$r" || true; \
       done

# Segmentation weights, in the folders ComfyUI-RMBG's SegmentV2 node reads from
# (models/grounding-dino and models/SAM under the ComfyUI install).
RUN comfy model download --url https://huggingface.co/1038lab/GroundingDINO/resolve/main/GroundingDINO_SwinT_OGC.cfg.py \
        --relative-path models/grounding-dino --filename GroundingDINO_SwinT_OGC.cfg.py \
    && comfy model download --url https://huggingface.co/1038lab/GroundingDINO/resolve/main/groundingdino_swint_ogc.pth \
        --relative-path models/grounding-dino --filename groundingdino_swint_ogc.pth \
    && comfy model download --url https://huggingface.co/1038lab/sam/resolve/main/sam_hq_vit_h.pth \
        --relative-path models/SAM --filename sam_hq_vit_h.pth

# LaMa inpainting weights for ComfyUI-RMBG's AILab_LamaRemover (object removal without ghosts).
RUN comfy model download --url https://huggingface.co/1038lab/Lama/resolve/main/big-lama.pt \
        --relative-path models/RMBG/Lama --filename big-lama.pt

# 2x decode for the painter. Qwen-Image kept the Wan 2.1 encoder, so the Wan2.1 2x upscale VAE
# (spacepxl, Apache-2.0) can turn the painter's ~1 MP latent into a ~4 MP image. Fills are then
# shrunk onto the full-size photo instead of enlarged 1.4-2.3x, the cause of the soft, grid-textured
# fills in the 2026-10-08 independent 100% review. Its decode needs the pack's own nodes
# (VAEUtils_CustomVAELoader + VAEUtils_VAEDecodeTiled, spacepxl/ComfyUI-VAE-Utils, MIT, no extra
# requirements), pinned to the merge of PR #28 (2026-08-25), which fixed loading on current ComfyUI.
RUN git clone https://github.com/spacepxl/ComfyUI-VAE-Utils /comfyui/custom_nodes/ComfyUI-VAE-Utils \
    && git -C /comfyui/custom_nodes/ComfyUI-VAE-Utils checkout 4c62ea005897fafbc593d69bedb8308ec9f932fd \
    && comfy model download --url https://huggingface.co/spacepxl/Wan2.1-VAE-upscale2x/resolve/main/Wan2.1_VAE_upscale2x_imageonly_real_v1.safetensors \
        --relative-path models/vae --filename Wan2.1_VAE_upscale2x_imageonly_real_v1.safetensors

# The 8-step Lightning LoRA trained for Qwen-Image-Edit-2511 (lightx2v, Apache-2.0). Until 2026-10-08
# the 2511 painter ran with the 2509 LoRA, the only one on the volume.
RUN comfy model download --url https://huggingface.co/lightx2v/Qwen-Image-Edit-2511-Lightning/resolve/main/Qwen-Image-Edit-2511-Lightning-8steps-V1.0-bf16.safetensors \
        --relative-path models/loras --filename Qwen-Image-Edit-2511-Lightning-8steps-V1.0-bf16.safetensors

# Object-removal adapter for Qwen-Image-Edit-2511 (prithivMLmods/QIE-2511-Object-Remover-v2,
# Apache-2.0, 0.24 GB): removes the object marked in red ("Remove the red highlighted object"),
# so a user's brush stroke can be its mark. Baked for the bench A/B against the plain painter.
RUN comfy model download --url https://huggingface.co/prithivMLmods/QIE-2511-Object-Remover-v2/resolve/main/Qwen-Image-Edit-2511-Object-Remover-v2-9200.safetensors \
        --relative-path models/loras --filename Qwen-Image-Edit-2511-Object-Remover-v2-9200.safetensors

# Quieter logs than the base image's DEBUG default.
ENV COMFY_LOG_LEVEL=INFO
