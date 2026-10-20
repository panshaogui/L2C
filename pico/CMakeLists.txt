cmake_minimum_required(VERSION 3.13)

# 1. 引入 Raspberry Pi Pico SDK 核心
include($ENV{PICO_SDK_PATH}/external/pico_sdk_import.cmake)

project(l2c_pico_firmware C CXX ASM)
cmake_policy(SET CMP0079 NEW)

pico_sdk_init()

# 2. 引入你的 L2C 编译器吐出来的 main.c
# 定义生成的头文件路径
set(PIO_HEADER ${CMAKE_CURRENT_SOURCE_DIR}/l2c_hardware.pio.h)
set(PIO_SOURCE ${CMAKE_CURRENT_SOURCE_DIR}/l2c_hardware.pio)

# 使用 pioasm 自动生成头文件
add_custom_command(
    OUTPUT ${PIO_HEADER}
    DEPENDS ${PIO_SOURCE}
    COMMAND pioasm -o c-sdk ${PIO_SOURCE} ${PIO_HEADER}
    COMMENT "Generating PIO header from l2c_hardware.pio"
)

# 将生成的头文件附加到可执行文件依赖中
add_executable(firmware main.c ${PIO_HEADER})

# 3. 源码打包编进固件
target_sources(firmware PRIVATE
    main.c
)

# 4. 指定头文件查找路径
target_include_directories(firmware PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/../clib
)

# 5. 链接 Pico 基础硬件库（GPIO、串口等）
# 在这里追加 hardware_adc 模块，打通 ADC 头文件与底层驱动！
target_link_libraries(firmware pico_stdlib pico_multicore hardware_adc hardware_dma hardware_irq hardware_pio hardware_clocks)

# === 在这里插入：强制开启 USB 虚拟串口，关闭物理 UART ===
pico_enable_stdio_usb(firmware 1)
pico_enable_stdio_uart(firmware 0)

target_compile_options(firmware PRIVATE
    -mcpu=cortex-m0plus
    -mthumb
    -Wa,-mthumb       # 强行给底层的内联汇编器注入 Thumb 指令集锁
)

target_link_options(firmware PRIVATE
    -mcpu=cortex-m0plus
    -mthumb
)

# 6. 激活全自动固件转换，自动生成可以直接拖进单片机 U 盘的 firmware.uf2
pico_add_extra_outputs(firmware)

