// ==============================================================================
// Copyright (c) 2026 Panshaogui | MIT License
// L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
// ==============================================================================

#include "hardware/pio.h"
#include "l2c_hardware.pio.h" // 引入您刚才通过 pioasm 生成的头文件

// ==============================================
// L2C 逻辑分析仪 (MVP) 专用高速数据拉取桥梁
// ==============================================
static inline void c_pio_la_init(int pin_base, int pin_clk) {
    PIO pio = pio0; uint sm = 1; // 使用状态机 1 避免与 blink 冲突
    uint offset = pio_add_program(pio, &la_reader_program); // L2C 会自动生成 la_reader_program
    pio_sm_config c = la_reader_program_get_default_config(offset);
    
    // 配置 8 位输入总线
    sm_config_set_in_pins(&c, pin_base);
    for(int i=0; i<8; i++) pio_gpio_init(pio, pin_base + i);
    pio_sm_set_consecutive_pindirs(pio, sm, pin_base, 8, false);
    
    // 配置 1 位输出时钟 (向 FPGA 发号施令)
    sm_config_set_set_pins(&c, pin_clk, 1);
    pio_gpio_init(pio, pin_clk);
    pio_sm_set_consecutive_pindirs(pio, sm, pin_clk, 1, true);
    
    sm_config_set_in_shift(&c, false, true, 8); // 8 bit 自动推入 FIFO
    sm_config_set_clkdiv(&c, 10.0f); // 适度降速确保杜邦线电气安全
    
    pio_sm_init(pio, sm, offset, &c);
    pio_sm_set_enabled(pio, sm, true);
}

static inline uint32_t c_pio_la_read_fifo() {
    return pio_sm_get_blocking(pio0, 1);
}
