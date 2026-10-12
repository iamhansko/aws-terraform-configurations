# The blueprint's comfyui_aws_stack/docker/Dockerfile (aws-samples/cost-effective-aws-deployment-of-comfyui at
# b7d3250), which its DockerImageAsset built during cdk deploy. One line differs: the base image comes from
# nvcr.io rather than Docker Hub. The two registries serve the same image under this tag - the same manifest
# digest, sha256:d1ad87e98b335faaf097f2b6772dc4eec20b4516bac175761c30c91490a3f9cf, when this was checked - and
# Docker Hub limits anonymous pulls per source address, which CodeBuild shares with every other build in the
# region. A limited pull fails the build with "toomanyrequests" and the apply with it.
#
# This directory is the build context: its files, by name and content, are hashed into the image tag
# (main.tf), so editing anything here builds and rolls out a new image on the next apply.
FROM nvcr.io/nvidia/cuda:12.9.0-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=America/Los_Angeles

# Install dependencies
RUN apt-get update && apt-get install -y \
    git \
    make build-essential libssl-dev zlib1g-dev \
    libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm \
    libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev git git-lfs  \
    ffmpeg libsm6 libxext6 cmake libgl1-mesa-glx \
    && rm -rf /var/lib/apt/lists/* \
    && git lfs install

# Create and switch to a new user
RUN useradd -m -u 1000 user
USER user
ENV HOME=/home/user \
    PATH=/home/user/.local/bin:$PATH
RUN mkdir -p /home/user/opt/ComfyUI && chown -R user /home/user/opt/ComfyUI

# Pyenv and Python setup
RUN curl https://pyenv.run | bash
ENV PATH=$HOME/.pyenv/shims:$HOME/.pyenv/bin:$PATH
ENV PYTHON_VERSION=3.12.0
RUN pyenv install $PYTHON_VERSION && \
    pyenv global $PYTHON_VERSION && \
    pip install --no-cache-dir --upgrade pip setuptools wheel && \
    pip install --no-cache-dir torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu126

# Set the working directory
WORKDIR /home/user/opt/ComfyUI

# Clone ComfyUI and ComfyUI-Manager
RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI . && \
    mkdir -p custom_nodes/ComfyUI-Manager && \
    git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager custom_nodes/ComfyUI-Manager

# Install requirements from cloned repositories
RUN pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir -r custom_nodes/ComfyUI-Manager/requirements.txt

# Copy the configuration file
COPY comfyui_config/extra_model_paths.yaml ./extra_model_paths.yaml

CMD ["python", "/home/user/opt/ComfyUI/main.py", "--listen", "0.0.0.0", "--port", "8181", "--output-directory", "/home/user/opt/ComfyUI/output/"]
