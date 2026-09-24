#!/bin/bash
# L2C ESP32-S3 自建极速容器交叉编译触发器 (双底盘智能适配版)

IMAGE_NAME="l2c-esp32s3-env:local"

# 0. 战术目标校验
BOARD_TYPE=$1
if [ "$BOARD_TYPE" != "eora" ] && [ "$BOARD_TYPE" != "waveshare" ]; then
    echo " 错误：未指定或未知的物理底盘！"
    echo " 用法: ./build_esp32s3.sh [ eora | waveshare ]"
    echo " - eora      : 亿佰特 EoRa-S3 (4MB Flash, 无 PSRAM, 挂载 OTA 分区)"
    echo " - waveshare : 微雪 Touch-LCD-2 (16MB Flash, 8MB Octal-PSRAM, 视觉主板)"
    exit 1
fi

echo " 1. 正在清理宿主机本地残留的脏缓存..."
rm -rf "$(pwd)/esp32/build"
rm -f "$(pwd)/esp32/CMakeCache.txt"
rm -f "$(pwd)/esp32/sdkconfig" 

echo " 2. 正在烧写全局基础路由表 (Native USB + NimBLE)..."
echo "CONFIG_ESP_CONSOLE_USB_SERIAL_JTAG=y" > "$(pwd)/esp32/sdkconfig.defaults"
echo "CONFIG_ESP_CONSOLE_SECONDARY_NONE=y" >> "$(pwd)/esp32/sdkconfig.defaults"
echo "CONFIG_BT_ENABLED=y" >> "$(pwd)/esp32/sdkconfig.defaults"
echo "CONFIG_BT_NIMBLE_ENABLED=y" >> "$(pwd)/esp32/sdkconfig.defaults"

# ==============================================================================
# [核心逻辑] 根据目标板型，注入专属的物理法则！
# ==============================================================================
if [ "$BOARD_TYPE" == "waveshare" ]; then
    echo " [微雪机甲] 注入 8MB 八线 PSRAM 与 16MB 专属 OTA 图纸..."
    echo "CONFIG_ESP32S3_SPIRAM_SUPPORT=y" >> "$(pwd)/esp32/sdkconfig.defaults"
    echo "CONFIG_SPIRAM=y" >> "$(pwd)/esp32/sdkconfig.defaults"
    echo "CONFIG_SPIRAM_MODE_OCT=y" >> "$(pwd)/esp32/sdkconfig.defaults"
    echo "CONFIG_SPIRAM_SPEED_80M=y" >> "$(pwd)/esp32/sdkconfig.defaults"
    echo "CONFIG_SPIRAM_FETCH_INSTRUCTIONS=y" >> "$(pwd)/esp32/sdkconfig.defaults"
    echo "CONFIG_SPIRAM_RODATA=y" >> "$(pwd)/esp32/sdkconfig.defaults"
    
    # 强制 16MB 并挂载微雪专属图纸
    echo "CONFIG_ESPTOOLPY_FLASHSIZE_16MB=y" >> "$(pwd)/esp32/sdkconfig.defaults"
    echo "CONFIG_PARTITION_TABLE_CUSTOM=y" >> "$(pwd)/esp32/sdkconfig.defaults"
    echo "CONFIG_PARTITION_TABLE_CUSTOM_FILENAME=\"partitions_waveshare.csv\"" >> "$(pwd)/esp32/sdkconfig.defaults"
    echo "CONFIG_PARTITION_TABLE_OFFSET=0x8000" >> "$(pwd)/esp32/sdkconfig.defaults"

elif [ "$BOARD_TYPE" == "eora" ]; then
    echo " [亿佰特雷达] 注入 4MB 空间压榨法则与 专属 OTA 图纸..."
    echo "CONFIG_ESPTOOLPY_FLASHSIZE_4MB=y" >> "$(pwd)/esp32/sdkconfig.defaults"
    echo "CONFIG_PARTITION_TABLE_CUSTOM=y" >> "$(pwd)/esp32/sdkconfig.defaults"
    echo "CONFIG_PARTITION_TABLE_CUSTOM_FILENAME=\"partitions_eora.csv\"" >> "$(pwd)/esp32/sdkconfig.defaults"
    echo "CONFIG_PARTITION_TABLE_OFFSET=0x8000" >> "$(pwd)/esp32/sdkconfig.defaults"
fi
# ==============================================================================

if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    echo " 3. 正在锻造极速炼丹炉..."
    docker build -t "$IMAGE_NAME" -f Dockerfile.esp32s3 .
fi

echo " 4. 跨维启动！锁定靶标 $BOARD_TYPE 点火编译！"
docker run --rm \
    -v "$(pwd)":/project \
    -w /project/esp32 \
    "$IMAGE_NAME" /bin/bash -c "idf.py set-target esp32s3 && idf.py build"

echo " 编译完成！[$BOARD_TYPE] 专属极速固件已生成！"