FROM pytorch/pytorch:2.7.1-cuda12.8-cudnn9-devel

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

COPY requirements.txt /app/requirements.txt

RUN apt-get update && apt-get install -y --no-install-recommends \
    g++ \
    wget \
    curl \
    unzip \
    ffmpeg \
    libsm6 \
    libxext6 \
    libvulkan1 \
    git \
    openssh-client \
 && python -m pip install --upgrade pip setuptools wheel \
 && python -m pip install \
    torch==2.7.1 \
    torchvision==0.22.1 \
    torchaudio==2.7.1 \
    --index-url https://download.pytorch.org/whl/cu128 \
 && python -m pip install -r /app/requirements.txt \
 && python -m pip install -U bitsandbytes \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

COPY . /app

ENV PYTHONPATH=/app

ARG PRELOAD_MODELS=1
ARG MIT_RELEASE_BASE="https://github.com/zyddnys/manga-image-translator/releases/download/beta-0.3"
ARG MIT_RELEASE_MIRROR1="https://ghfast.top/https://github.com/zyddnys/manga-image-translator/releases/download/beta-0.3"
ARG MIT_RELEASE_MIRROR2="https://ghproxy.com/https://github.com/zyddnys/manga-image-translator/releases/download/beta-0.3"
ARG LAMA_LARGE_URL="https://huggingface.co/dreMaz/AnimeMangaInpainting/resolve/main/lama_large_512px.ckpt"
ARG LAMA_LARGE_MIRROR="https://hf-mirror.com/dreMaz/AnimeMangaInpainting/resolve/main/lama_large_512px.ckpt"

RUN if [ "$PRELOAD_MODELS" = "1" ]; then \
      set -eux; \
      mkdir -p /app/models/detection /app/models/ocr /app/models/inpainting /tmp/mit_models; \
      download_with_fallback() { \
        out="$1"; shift; \
        rm -f "${out}.part"; \
        for url in "$@"; do \
          [ -n "$url" ] || continue; \
          if wget -q --tries=3 --timeout=30 -O "${out}.part" "$url"; then \
            if [ -s "${out}.part" ]; then \
              mv "${out}.part" "$out"; \
              echo "downloaded: $out from $url"; \
              return 0; \
            fi; \
          fi; \
          rm -f "${out}.part"; \
        done; \
        echo "failed download: $out" >&2; \
        return 1; \
      }; \
      # Detection / OCR / Inpainting core models
      download_with_fallback /app/models/detection/detect-20241225.ckpt \
        "$MIT_RELEASE_BASE/detect-20241225.ckpt" \
        "$MIT_RELEASE_MIRROR1/detect-20241225.ckpt" \
        "$MIT_RELEASE_MIRROR2/detect-20241225.ckpt"; \
      download_with_fallback /app/models/detection/detect.ckpt \
        "$MIT_RELEASE_BASE/detect.ckpt" \
        "$MIT_RELEASE_MIRROR1/detect.ckpt" \
        "$MIT_RELEASE_MIRROR2/detect.ckpt"; \
      download_with_fallback /app/models/ocr/ocr_ar_48px.ckpt \
        "$MIT_RELEASE_BASE/ocr_ar_48px.ckpt" \
        "$MIT_RELEASE_MIRROR1/ocr_ar_48px.ckpt" \
        "$MIT_RELEASE_MIRROR2/ocr_ar_48px.ckpt"; \
      download_with_fallback /app/models/ocr/alphabet-all-v7.txt \
        "$MIT_RELEASE_BASE/alphabet-all-v7.txt" \
        "$MIT_RELEASE_MIRROR1/alphabet-all-v7.txt" \
        "$MIT_RELEASE_MIRROR2/alphabet-all-v7.txt"; \
      download_with_fallback /app/models/detection/comictextdetector.pt \
        "$MIT_RELEASE_BASE/comictextdetector.pt" \
        "$MIT_RELEASE_MIRROR1/comictextdetector.pt" \
        "$MIT_RELEASE_MIRROR2/comictextdetector.pt"; \
      download_with_fallback /app/models/detection/comictextdetector.pt.onnx \
        "$MIT_RELEASE_BASE/comictextdetector.pt.onnx" \
        "$MIT_RELEASE_MIRROR1/comictextdetector.pt.onnx" \
        "$MIT_RELEASE_MIRROR2/comictextdetector.pt.onnx"; \
      download_with_fallback /app/models/inpainting/inpainting_lama_mpe.ckpt \
        "$MIT_RELEASE_BASE/inpainting_lama_mpe.ckpt" \
        "$MIT_RELEASE_MIRROR1/inpainting_lama_mpe.ckpt" \
        "$MIT_RELEASE_MIRROR2/inpainting_lama_mpe.ckpt"; \
      download_with_fallback /app/models/inpainting/inpainting.ckpt \
        "$MIT_RELEASE_BASE/inpainting.ckpt" \
        "$MIT_RELEASE_MIRROR1/inpainting.ckpt" \
        "$MIT_RELEASE_MIRROR2/inpainting.ckpt"; \
      # OCR legacy archives (extract ocr.ckpt / ocr-ctc.ckpt and dictionaries)
      download_with_fallback /tmp/mit_models/ocr.zip \
        "$MIT_RELEASE_BASE/ocr.zip" \
        "$MIT_RELEASE_MIRROR1/ocr.zip" \
        "$MIT_RELEASE_MIRROR2/ocr.zip"; \
      unzip -o /tmp/mit_models/ocr.zip -d /app/models/ocr >/dev/null; \
      download_with_fallback /tmp/mit_models/ocr-ctc.zip \
        "$MIT_RELEASE_BASE/ocr-ctc.zip" \
        "$MIT_RELEASE_MIRROR1/ocr-ctc.zip" \
        "$MIT_RELEASE_MIRROR2/ocr-ctc.zip"; \
      unzip -o /tmp/mit_models/ocr-ctc.zip -d /app/models/ocr >/dev/null; \
      # Lama large model is hosted on HuggingFace (not in beta-0.3 release assets)
      download_with_fallback /app/models/inpainting/lama_large_512px.ckpt \
        "$LAMA_LARGE_URL" \
        "$LAMA_LARGE_MIRROR"; \
      # Guardrails: fail build if critical models are missing/empty
      test -s /app/models/detection/detect-20241225.ckpt; \
      test -s /app/models/ocr/ocr_ar_48px.ckpt; \
      test -s /app/models/ocr/alphabet-all-v7.txt; \
      test -s /app/models/inpainting/inpainting_lama_mpe.ckpt; \
      test -s /app/models/inpainting/lama_large_512px.ckpt; \
      rm -rf /tmp/mit_models; \
    fi

ENTRYPOINT ["python", "-m", "manga_translator"]
