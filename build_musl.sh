#!/bin/bash
# build_linux.sh

IMAGE_NAME="ghcr.io/panshaogui/l2c-musl-env:latest"

if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "正在为您自动构建 Alpine Musl 炼丹炉，这只需一分钟..."
    docker pull "$IMAGE_NAME" .
fi

echo "启动 L2C Musl 容器编译集群..."
docker run --rm -v "$(pwd)":/workspace "$IMAGE_NAME" lua l2c.lua "$@"
