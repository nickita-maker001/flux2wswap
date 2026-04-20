#!/bin/bash
set -e
source /venv/main/bin/activate 2>/dev/null || true

WORKSPACE=${WORKSPACE:-/workspace}
COMFYUI_DIR="${WORKSPACE}/ComfyUI"

echo "=== FLUX.2-klein-9B + ComfyUI 0.19.3 Provisioning ==="

# === NODES для FLUX ===
NODES=(
    "https://github.com/black-forest-labs/ComfyUI-Flux"
    "https://github.com/ltdrdata/ComfyUI-Manager"
    "https://github.com/yolain/ComfyUI-Easy-Use"
    "https://github.com/kijai/ComfyUI-KJNodes"
    "https://github.com/cubiq/ComfyUI_essentials"
    "https://github.com/rgthree/rgthree-comfy"
)

# === МОДЕЛИ (с авторизацией через HF_TOKEN) ===
DIFFUSION_MODELS=(
    "https://huggingface.co/black-forest-labs/FLUX.2-klein-9B/resolve/main/flux-2-klein-9b.safetensors"
)

VAE_MODELS=(
    "https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/vae/flux2-vae.safetensors"
)

CLIP_MODELS=(
    "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp16.safetensors"
    "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors"
)

CLIP_VISION=(
    "https://huggingface.co/Comfy-Org/sigclip_vision_patch14_384/resolve/main/sigclip_vision_patch14_384.safetensors"
)

# === ФУНКЦИИ ===

clone_comfyui_if_needed() {
    if [[ ! -d "${COMFYUI_DIR}" ]]; then
        echo "→ Cloning ComfyUI..."
        git clone https://github.com/comfyanonymous/ComfyUI.git "${COMFYUI_DIR}"
    fi
    cd "${COMFYUI_DIR}"
}

install_nodes() {
    mkdir -p "${COMFYUI_DIR}/custom_nodes"
    cd "${COMFYUI_DIR}/custom_nodes"
    
    for repo in "${NODES[@]}"; do
        dir="${repo##*/}"
        if [[ -d "$dir" ]]; then
            echo "→ Updating $dir"
            (cd "$dir" && git pull --ff-only 2>/dev/null || git reset --hard origin/main)
        else
            echo "→ Cloning $dir"
            git clone "$repo" "$dir" --recursive || continue
        fi
        [[ -f "$dir/requirements.txt" ]] && pip install --no-cache-dir -r "$dir/requirements.txt" 2>/dev/null || true
    done
}

download_with_auth() {
    local dir="$1"
    shift
    local files=("$@")
    mkdir -p "$dir"
    
    for url in "${files[@]}"; do
        echo "→ $url"
        local auth=""
        if [[ -n "$HF_TOKEN" && "$url" =~ huggingface\.co ]]; then
            auth="--header=\"Authorization: Bearer $HF_TOKEN\""
        fi
        # Используем eval для корректной обработки кавычек в заголовке
        eval wget -nc --content-disposition --show-progress -e dotbytes=4M $auth -P "$dir" "$url" || echo " [!] Failed: $url"
    done
}

install_extra_pip() {
    pip install --no-cache-dir transformers accelerate sentencepiece 2>/dev/null || true
}

# === MAIN ===
echo "🔧 Setting up environment..."
clone_comfyui_if_needed
install_extra_pip
install_nodes

echo "📦 Downloading models..."
download_with_auth "${COMFYUI_DIR}/models/diffusion_models" "${DIFFUSION_MODELS[@]}"
download_with_auth "${COMFYUI_DIR}/models/vae" "${VAE_MODELS[@]}"
download_with_auth "${COMFYUI_DIR}/models/clip" "${CLIP_MODELS[@]}"
download_with_auth "${COMFYUI_DIR}/models/clip_vision" "${CLIP_VISION[@]}"

echo "✅ Provisioning complete!"