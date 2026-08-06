-- ==============================================
-- examples/04_test_pio.tl: L2C PIO HLS 硬件综合器端到端测试
-- ==============================================

-- @l2c_include: clib/pio_helpers.h
-- @l2c_import: std/pico.tl

-- 1. 思想域：声明并编写硬件状态机 (将被 HLS 拦截，转化为 blink.pio)
-- 注意：引号在编译时会被 HLS 引擎聪明地剥离
local function L2C_PIO_blink()
    set("pindirs", 1)
    
    ::loop::
    set("pins", 1)
    set("x", 31)
    ::delay_x::
    set("y", 31)
    ::delay_y::
    jmp("y--", "delay_y")
    jmp("x--", "delay_x")

    set("pins", 0)
    set("x", 31)
    ::delay_x_off::
    set("y", 31)
    ::delay_y_off::
    jmp("y--", "delay_y_off")
    jmp("x--", "delay_x_off")

    jmp("loop")
end

-- 2. 物理域：定义 C 头文件中暴露的 FFI 包装器
local type C_PIO_HELPERS = record
c_pio_blink_start: function(integer)
end

-- ===============================================
-- 3. 业务入口 (绝对禁止使用 global function main 包裹！)
-- ===============================================

-- 唤醒 125MHz 系统时钟锁相环，并打通 UART (GP0/GP1) 物理串口！

C_PICO.stdio_init_all()
print(" L2C HLS PIO Test Booting (Bare-Metal)...")

-- 如果你是 Pico W，请拿根线把 LED 接到 GPIO 15 (Pin 20) 上！
-- 如果你是老款无 WiFi 的 Pico，这里填 25 即可！

local led_pin = 25
C_PIO_HELPERS.c_pio_blink_start(led_pin)

print(" PIO 硬件状态机已成功接管物理引脚: " , led_pin)

while true do
-- 此时 CPU 可以随心所欲休眠，LED 的闪烁完全由 PIO 独立芯片执行！
C_PICO.sleep_us(1000000)
print(" 主 CPU 心跳正常，PIO 正在后台闪烁...")
end
