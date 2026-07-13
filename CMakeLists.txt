cmake_minimum_required(VERSION 3.13)

# 1. 引入 Raspberry Pi Pico SDK 核心
include($ENV{PICO_SDK_PATH}/external/pico_sdk_import.cmake)

project(l2c_pico_firmware C CXX ASM)
cmake_policy(SET CMP0079 NEW)

pico_sdk_init()

# 2. 引入你的 L2C 编译器吐出来的 main.c
add_executable(firmware main.c)

# 3. 强行把 FreeRTOS 内核源码打包编进固件
set(FREERTOS_DIR $ENV{FREERTOS_KERNEL_PATH})
target_sources(firmware PRIVATE
    main.c
    ${FREERTOS_DIR}/tasks.c
    ${FREERTOS_DIR}/list.c
    ${FREERTOS_DIR}/queue.c
    ${FREERTOS_DIR}/timers.c
    ${FREERTOS_DIR}/portable/GCC/ARM_CM0/port.c
    ${FREERTOS_DIR}/portable/GCC/ARM_CM0/portasm.c
    ${FREERTOS_DIR}/portable/MemMang/heap_4.c
)

# 4. 指定头文件查找路径（包含 FreeRTOS 硬件层）
target_include_directories(firmware PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${FREERTOS_DIR}/include
    ${FREERTOS_DIR}/portable/GCC/ARM_CM0
)

# 5. 链接 Pico 基础硬件库（GPIO、串口等）
target_link_libraries(firmware pico_stdlib)
# 🔥 核心修复：在这里追加 hardware_adc 模块，打通 ADC 头文件与底层驱动！
target_link_libraries(firmware pico_stdlib hardware_adc)

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
