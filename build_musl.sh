#!/bin/bash
# build_musl.sh

IMAGE_NAME="l2c-musl-forge:v1"

if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "⚠️ 正在为您自动构建 Alpine Musl 炼丹炉，这只需一分钟..."
    docker build -f Dockerfile.musl -t "$IMAGE_NAME" .
fi

echo " 启动 L2C Musl 容器编译集群..."
docker run --rm -v "$(pwd)":/workspace "$IMAGE_NAME" "$@"
