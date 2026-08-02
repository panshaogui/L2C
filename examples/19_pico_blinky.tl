-- examples/19_pico_blinky.tl
-- @l2c_import: std/pico.tl

-- 1. 🔥【Pico 救命第一行】必须初始化 Pico 标准库（硬件 UART / USB 以及外设时钟）
C_PICO.stdio_init_all()

print("🚀 L2C Pico 裸机内核已苏醒！准备接管 RP2040 物理引脚...")

-- 2. Pico 板载 LED 引脚为 GP25
local LED_PIN = 25
C_PICO.gpio_init(LED_PIN)
C_PICO.gpio_set_dir(LED_PIN, PICO_GPIO_OUT)

local current_level = 0

-- 3. 裸机死循环闪烁
while true do
    current_level = 1 - current_level
    C_PICO.gpio_put(LED_PIN, current_level)
    
    if current_level == 1 then
        print("💡 [Pico 裸机] LED 点亮 (GP25 -> 1)")
    else
        print("🌙 [Pico 裸机] LED 熄灭 (GP25 -> 0)")
    end
    
    -- 使用 Pico 专属的高精度微秒休眠 (500ms = 500000us)
    C_PICO.sleep_us(500000)
end

