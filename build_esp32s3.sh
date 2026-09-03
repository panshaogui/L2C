#!/bin/bash
# L2C ESP32-S3 自建极速容器交叉编译触发器

# 改用本地镜像名，切断与云端旧版 ghcr.io 镜像的联系！
IMAGE_NAME="l2c-esp32s3-env:local"

# 1. 物理粉碎宿主机残留的恶心缓存，防止它死锁芯片型号
echo " 1. 正在清理宿主机本地残留的脏缓存..."
rm -rf "$(pwd)/esp32/build"
rm -f "$(pwd)/esp32/CMakeCache.txt"
rm -f "$(pwd)/esp32/sdkconfig" # 极其关键：必须删掉旧的芯片配置文件！

# 强制注入原生 USB 控制台路由配置
echo " 2. 正在烧写 Native USB 路由表..."
echo "CONFIG_ESP_CONSOLE_USB_SERIAL_JTAG=y" > "$(pwd)/esp32/sdkconfig.defaults"
echo "CONFIG_ESP_CONSOLE_SECONDARY_NONE=y" >> "$(pwd)/esp32/sdkconfig.defaults"

# 强行激活 NimBLE 蓝牙 5.0 协议栈
echo "CONFIG_BT_ENABLED=y" >> "$(pwd)/esp32/sdkconfig.defaults"
echo "CONFIG_BT_NIMBLE_ENABLED=y" >> "$(pwd)/esp32/sdkconfig.defaults"

# 2. 检查极速炼丹炉是否存在，如果不存在则使用本地 Dockerfile 真实构建！
if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    echo " 2. 正在根据本地 Dockerfile.esp32 锻造含有 S3 架构的极速炼丹炉 (可能需要几分钟)..."
    docker build -t "$IMAGE_NAME" -f Dockerfile.esp32s3 .
fi

# 3. 跨维启动！强行切换 S3 靶标并点火编译！
echo " 3. 正在启动炼丹炉并锁定目标为 esp32s3..."
docker run --rm \
    -v "$(pwd)/esp32":/project \
    -w /project \
    "$IMAGE_NAME" /bin/bash -c "idf.py set-target esp32s3 && idf.py build"

echo " 4. 编译完成！S3 极速固件已生成于 esp32/build/ 目录下！"