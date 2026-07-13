-- ==============================================================================
-- Copyright (c) 2026 L2C Architect | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- std/esp32.tl
-- @l2c_include: driver/gpio.h
-- @l2c_include: freertos/FreeRTOS.h
-- @l2c_include: freertos/task.h

-- 映射 ESP-IDF 底层 C API
local type C_ESP32 = record
    -- gpio_reset_pin(gpio_num_t pin)
    gpio_reset_pin: function(integer): integer
    -- gpio_set_direction(gpio_num_t pin, gpio_mode_t mode)
    gpio_set_direction: function(integer, integer): integer
    -- gpio_set_level(gpio_num_t pin, uint32_t level)
    gpio_set_level: function(integer, integer): integer
    -- vTaskDelay(TickType_t ticks)
    vTaskDelay: function(integer)
end

-- 扁平化导出常量 (ESP32 的 GPIO_MODE_OUTPUT 枚举值通常为 2)
local ESP_GPIO_MODE_OUTPUT: integer = 2

-- 极简封装
local function esp32_delay_ms(ms: integer)
    -- ESP-IDF 中，通常 1 tick = 10ms (Hz=100)，或者 1 tick = 1ms (Hz=1000)
    -- 🔥 [核心修复]：使用向下取整除法 //，确保返回绝对的 integer 给底层的 C 语言！
    C_ESP32.vTaskDelay(ms // 10) 
end
