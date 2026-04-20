#!/bin/bash
set -e
source /venv/main/bin/activate 2>/dev/null || true

WORKSPACE=${WORKSPACE:-/workspace}
COMFYUI_DIR="${WORKSPACE}/ComfyUI"

echo "=== FLUX.2-klein-9B FP8 + Qwen3-8B FP8 + ComfyUI 0.19.3 ==="

# === CUSTOM NODES (из воркфлоу) ===
NODES=(
    "https://github.com/black-forest-labs/ComfyUI-Flux"
    "https://github.com/ltdrdata/ComfyUI-Manager"
    "https://github.com/yolain/ComfyUI-Easy-Use"
    "https://github.com/kijai/ComfyUI-KJNodes"
    "https://github.com/cubiq/ComfyUI_essentials"
    "https://github.com/rgthree/rgthree-comfy"
    "https://github.com/lquesada/ComfyUI-Inpaint-CropAndStitch"
    "https://github.com/chflame163/ComfyUI_LayerStyle"
    "https://github.com/Smirnov75/ComfyUI-mxToolkit"
    "https://github.com/ltdrdata/ComfyUI-Impact-Pack"
    "https://github.com/huchukato/ComfyUI-QwenVL-Mod"
    "https://github.com/bash-j/mikey_nodes"
    "https://github.com/Suzie1/ComfyUI_Comfyroll_CustomNodes"
    "https://github.com/StableLlama/ComfyUI-basic_data_handling"
    "https://github.com/PGCRT/CRT-Nodes"
    "https://github.com/city96/ComfyUI-GGUF"
)

# === МОДЕЛИ: Пути ===
DIFFUSION_DIR="${COMFYUI_DIR}/models/diffusion_models"
TEXT_ENCODERS_DIR="${COMFYUI_DIR}/models/text_encoders"
VAE_DIR="${COMFYUI_DIR}/models/vae"
LLM_DIR="${COMFYUI_DIR}/models/LLM"

# === МОДЕЛИ: Ссылки (официальные, с поддержкой авторизации) ===
# 🔹 Диффузионная модель: пробует FP8, fallback на full
FLUX_FP8_URL="https://huggingface.co/black-forest-labs/FLUX.2-klein-9B/resolve/main/flux-2-klein-9b-fp8.safetensors"
FLUX_FULL_URL="https://huggingface.co/black-forest-labs/FLUX.2-klein-9B/resolve/main/flux-2-klein-9b.safetensors"

# 🔹 Текстовый энкодер: Qwen3-8B FP8 mixed (официальный от Comfy-Org)
QWEN_FP8_URL="https://huggingface.co/Comfy-Org/flux2-klein-9B/resolve/main/split_files/text_encoders/qwen_3_8b_fp8mixed.safetensors"
QWEN_FULL_URL="https://huggingface.co/Comfy-Org/flux2-klein-9B/resolve/main/split_files/text_encoders/qwen_3_8b.safetensors"

# 🔹 VAE (официальный)
VAE_URL="https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/vae/flux2-vae.safetensors"

# 🔹 Опционально: Qwen GGUF для нод типа ComfyUI-GGUF
QWEN_GGUF_URL="https://huggingface.co/mradermacher/Qwen3-8B-heretic-GGUF/resolve/main/Qwen3-8B-heretic.Q8_0.gguf"

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
            git clone "$repo" "$dir" --recursive || { echo " [!] Failed: $repo"; continue; }
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
        [[ -z "$url" ]] && continue
        echo "→ $url"
        local auth=""
        if [[ -n "$HF_TOKEN" && "$url" =~ huggingface\.co ]]; then
            auth="--header=\"Authorization: Bearer $HF_TOKEN\""
        fi
        eval wget -nc --content-disposition --show-progress -e dotbytes=4M $auth -P "$dir" "$url" || echo " [!] Failed: $url"
    done
}

download_with_fallback() {
    local target_file="$1"
    local primary_url="$2"
    local fallback_url="$3"
    local target_dir="$(dirname "$target_file")"
    
    mkdir -p "$target_dir"
    
    if [[ -f "$target_file" ]]; then
        echo "✅ Exists: $(basename "$target_file")"
        return 0
    fi
    
    echo "→ Trying primary: $primary_url"
    local auth=""
    if [[ -n "$HF_TOKEN" && "$primary_url" =~ huggingface\.co ]]; then
        auth="--header=\"Authorization: Bearer $HF_TOKEN\""
    fi
    
    if eval wget -nc --content-disposition --show-progress -e dotbytes=4M $auth -O "$target_file" "$primary_url" 2>/dev/null; then
        echo "✅ Downloaded: $(basename "$target_file")"
        return 0
    fi
    
    echo "⚠️ Primary failed, trying fallback: $fallback_url"
    if [[ -n "$HF_TOKEN" && "$fallback_url" =~ huggingface\.co ]]; then
        auth="--header=\"Authorization: Bearer $HF_TOKEN\""
    fi
    eval wget -nc --content-disposition --show-progress -e dotbytes=4M $auth -O "$target_file" "$fallback_url" || echo " [!] Failed: $(basename "$target_file")"
}

install_extra_pip() {
    pip install --no-cache-dir \
        transformers \
        accelerate \
        sentencepiece \
        huggingface-hub \
        einops \
        safetensors \
        2>/dev/null || true
}

# === MAIN ===
echo "🔧 Setting up environment..."
clone_comfyui_if_needed
install_extra_pip
install_nodes

echo "📦 Downloading FLUX.2-klein-9B (FP8 preferred)..."
download_with_fallback \
    "${DIFFUSION_DIR}/flux-2-klein-9b-fp8.safetensors" \
    "$FLUX_FP8_URL" \
    "$FLUX_FULL_URL"

echo "📦 Downloading Qwen3-8B text encoder (FP8 mixed preferred)..."
download_with_fallback \
    "${TEXT_ENCODERS_DIR}/qwen_3_8b_fp8mixed.safetensors" \
    "$QWEN_FP8_URL" \
    "$QWEN_FULL_URL"

echo "📦 Downloading FLUX.2 VAE..."
download_with_auth "${VAE_DIR}" "$VAE_URL"

echo "📦 Downloading Qwen3-8B GGUF (optional, for GGUF nodes)..."
if [[ -n "$HF_TOKEN" ]]; then
    mkdir -p "${LLM_DIR}/Qwen3-8B-heretic-GGUF"
    wget --header="Authorization: Bearer $HF_TOKEN" \
         -nc --content-disposition --show-progress -e dotbytes=4M \
         -P "${LLM_DIR}/Qwen3-8B-heretic-GGUF" "$QWEN_GGUF_URL" 2>/dev/null || \
         echo " [!] Optional Qwen GGUF skipped"
fi

echo ""
echo "✅ Provisioning complete!"
echo "📁 Model paths:"
echo "   • Diffusion: ${DIFFUSION_DIR}/flux-2-klein-9b-fp8.safetensors"
echo "   • Text Encoder: ${TEXT_ENCODERS_DIR}/qwen_3_8b_fp8mixed.safetensors"
echo "   • VAE: ${VAE_DIR}/flux2-vae.safetensors"
echo "   • LLM (optional): ${LLM_DIR}/Qwen3-8B-heretic-GGUF/"
echo ""
echo "🚀 ComfyUI will start on port 18188"
