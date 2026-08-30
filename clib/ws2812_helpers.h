// ==============================================================================
// Copyright (c) 2026 Panshaogui | MIT License
// L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
// ==============================================================================
  
#pragma once
#include "hardware/pio.h"
#include "hardware/clocks.h"
#include "l2c_hardware.pio.h"

static inline void c_pio_ws2812_init(int pin) {
    PIO pio = pio0; uint sm = 0;
    uint offset = pio_add_program(pio, &ws2812_program);
    pio_sm_config c = ws2812_program_get_default_config(offset);
    
    sm_config_set_set_pins(&c, pin, 1);
    pio_gpio_init(pio, pin);
    pio_sm_set_consecutive_pindirs(pio, sm, pin, 1, true);
    
    // false=左移(MSB), true=自动拉取, 24=满24位触发
    sm_config_set_out_shift(&c, false, true, 24);
    
    // 强制 8MHz PIO 时钟，1 个周期 = 125ns
    float div = clock_get_hz(clk_sys) / 8000000.0f;
    sm_config_set_clkdiv(&c, div);
    
    pio_sm_init(pio, sm, offset, &c);
    pio_sm_set_enabled(pio, sm, true);
}

static inline void c_pio_ws2812_put(uint8_t r, uint8_t g, uint8_t b) {
    // 拼装 GRB，左移 8 位配合 PIO 的 24-bit Auto-pull
    uint32_t grb = ((uint32_t)g << 16) | ((uint32_t)r << 8) | (uint32_t)b;
    pio_sm_put_blocking(pio0, 0, grb << 8); 
}
