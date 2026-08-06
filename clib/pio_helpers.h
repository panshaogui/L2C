// ==============================================================================
// Copyright (c) 2026 Panshaogui | MIT License
// L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
// ==============================================================================

#pragma once
#include "hardware/pio.h"
#include "l2c_hardware.pio.h" // 引入您刚才通过 pioasm 生成的头文件

// 暴露给 L2C Teal 脚本的极简点火开关
static inline void c_pio_blink_start(int pin) {
    PIO pio = pio0;
    uint sm = 0; // 使用状态机 0
    
    // 1. 将我们手搓的 PIO 汇编程序装载入硬件指令内存
    uint offset = pio_add_program(pio, &blink_program);
    
    // 2. 获取默认配置
    pio_sm_config c = blink_program_get_default_config(offset);
    
    // 3. 映射物理引脚 (LED)
    sm_config_set_set_pins(&c, pin, 1);
    pio_gpio_init(pio, pin);
    pio_sm_set_consecutive_pindirs(pio, sm, pin, 1, true);
    
    // 4. 时钟分频 (为了让肉眼能看到闪烁，将时钟放到极慢：每周期长达微秒级)
    sm_config_set_clkdiv(&c, 65535.0f);
    
    // 5. 初始化并启动硬件状态机！
    pio_sm_init(pio, sm, offset, &c);
    pio_sm_set_enabled(pio, sm, true);
}
