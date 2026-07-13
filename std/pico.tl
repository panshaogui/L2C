-- ==============================================================================
-- Copyright (c) 2026 L2C Architect | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- std/pico.tl
-- @l2c_include: pico/stdlib.h
-- @l2c_include: hardware/adc.h
-- @l2c_include: pico/time.h

local type C_PICO = record
    stdio_init_all: function()
    gpio_init: function(integer)
    gpio_set_dir: function(integer, integer)
    gpio_put: function(integer, integer)
    
    -- 🔥 扩容 ADC 麦克风采样接口
    adc_init: function()
    adc_gpio_init: function(integer)
    adc_select_input: function(integer)
    adc_read: function(): integer
    
    -- 🔥 扩容微秒级硬实时休眠（用于死死锁住 8000Hz 采样率）
    sleep_us: function(integer)
end

local PICO_GPIO_OUT: integer = 1
local PICO_GPIO_IN: integer = 0
