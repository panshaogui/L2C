-- examples/21_esp32_blinky.tl
-- @l2c_import: std/esp32.tl

print("🚀 L2C ESP32 核心已苏醒！准备接管 WROOM-32 物理引脚...")

-- 初始化 GPIO 2 (WROOM-32 板载蓝灯)
local LED_PIN = 2
C_ESP32.gpio_reset_pin(LED_PIN)
C_ESP32.gpio_set_direction(LED_PIN, ESP_GPIO_MODE_OUTPUT)

-- 无限循环闪烁，彻底交由底层 FreeRTOS 调度
while true do
    C_ESP32.gpio_set_level(LED_PIN, 1)
    esp32_delay_ms(500)
    
    C_ESP32.gpio_set_level(LED_PIN, 0)
    esp32_delay_ms(500)
end
