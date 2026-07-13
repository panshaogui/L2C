#!/bin/bash
# L2C ESP32 自建极速容器交叉编译触发器

IMAGE_NAME="l2c-esp32-forge:v1"

# 1. 物理粉碎宿主机残留的恶心缓存，防止它死锁芯片型号
echo "🧹 1. 正在清理宿主机本地残留的脏缓存..."
rm -rf "$(pwd)/esp32_forge/build"
rm -f "$(pwd)/esp32_forge/CMakeCache.txt"

# 2. 检查极速炼丹炉是否存在
if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "⚠️ 正在为您自动构建 ESP32 极速炼丹炉 (仅包含核心工具链)..."
    docker build -f Dockerfile.esp32 -t "$IMAGE_NAME" .
fi

docker run --rm \
    -v "$(pwd)/esp32_forge":/project \
    "$IMAGE_NAME" /bin/bash -c "idf.py build"

echo "✅ 编译完成！固件位于 esp32_forge/build/ 目录下！"
