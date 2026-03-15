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
    ffmpeg \
    libsm6 \
    libxext6 \
    gimp \
    libvulkan1 \
    git \
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

ENTRYPOINT ["python", "-m", "manga_translator"]
