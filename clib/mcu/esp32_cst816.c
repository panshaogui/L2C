// ==============================================================================
// Copyright (c) 2026 Panshaogui | MIT License
// L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
// ==============================================================================

#include "driver/i2c.h"

// 触摸屏 I2C 坐标 (基于 ESP32-S3-Touch-LCD-2 官方网表校准)
#define TOUCH_SCL 47 // NLTP0SCL NLIO47
#define TOUCH_SDA 48 // NLTP0SDA NLIO48
#define TOUCH_INT 46 // NLTP0INT NLIO46 (备用，未来可做硬件唤醒中断)
#define CST816_ADDR 0x15

static inline int l2c_touch_init() {
    i2c_config_t conf = {
        .mode = I2C_MODE_MASTER,
        .sda_io_num = TOUCH_SDA,
        .scl_io_num = TOUCH_SCL,
        .sda_pullup_en = GPIO_PULLUP_ENABLE,
        .scl_pullup_en = GPIO_PULLUP_ENABLE,
        .master.clk_speed = 400000, // 400KHz 极速 I2C
    };
    i2c_param_config(I2C_NUM_0, &conf);
    return i2c_driver_install(I2C_NUM_0, conf.mode, 0, 0, 0) == ESP_OK ? 1 : 0;
}

// 极速读取 CST816 坐标寄存器 (0-GC，返回压实后的 32位 整数)
// 格式: [Bit 31: Pressed(1/0)] [Bit 16~27: X坐标] [Bit 0~11: Y坐标]
static inline uint32_t l2c_touch_get_pos() {
    uint8_t data[6];
    i2c_cmd_handle_t cmd = i2c_cmd_link_create();
    i2c_master_start(cmd);
    i2c_master_write_byte(cmd, (CST816_ADDR << 1) | I2C_MASTER_WRITE, true);
    i2c_master_write_byte(cmd, 0x02, true); // 从 0x02 (手指数量) 寄存器开始读
    i2c_master_start(cmd);
    i2c_master_write_byte(cmd, (CST816_ADDR << 1) | I2C_MASTER_READ, true);
    i2c_master_read(cmd, data, 5, I2C_MASTER_ACK);
    i2c_master_read_byte(cmd, data + 5, I2C_MASTER_NACK);
    i2c_master_stop(cmd);
    
    if (i2c_master_cmd_begin(I2C_NUM_0, cmd, pdMS_TO_TICKS(10)) != ESP_OK) {
        i2c_cmd_link_delete(cmd);
        return 0;
    }
    i2c_cmd_link_delete(cmd);

    int fingers = data[0];
    if (fingers == 0) return 0; // 没摸

    /*
    // 1. 提取物理原生坐标 (Raw Data)
    int raw_x = ((data[1] & 0x0F) << 8) | data[2];
    int raw_y = ((data[3] & 0x0F) << 8) | data[4];
    
    // =========================================================
    // [战术触觉校准矩阵]：请根据您的实际横屏方向修改这里！
    // =========================================================
    int final_x = raw_x;
    int final_y = raw_y;

    // 动作A：X与Y轴对调 (保持 1，已经完美对齐了横竖维度)
    #define TOUCH_SWAP_XY  1
    // 动作B：X轴镜像反转 (保持 0，左右是正确的)
    #define TOUCH_INV_X    0
    // 动作C：Y轴镜像反转 (改成 1，强行把上下颠倒过来！)
    #define TOUCH_INV_Y    1

    if (TOUCH_SWAP_XY) {
        final_x = raw_y;
        final_y = raw_x;
    }
    // 注意：如果是横屏，最大宽度是 320，最大高度是 240！
    if (TOUCH_INV_X) final_x = 320 - final_x; 
    if (TOUCH_INV_Y) final_y = 240 - final_y;

    return (1 << 31) | (final_x << 16) | final_y;
    */

    // 1. 提取物理原生坐标 (Raw Data)
    int raw_x = ((data[1] & 0x0F) << 8) | data[2];
    int raw_y = ((data[3] & 0x0F) << 8) | data[4];
    
    int final_x = raw_x;
    int final_y = raw_y;

    // [竖屏基线定标] 全部清零，获取最原始的物理数据！
    #define TOUCH_SWAP_XY  0
    #define TOUCH_INV_X    0
    #define TOUCH_INV_Y    0

    if (TOUCH_SWAP_XY) {
        final_x = raw_y;
        final_y = raw_x;
    }
    // [注意边界] 竖屏模式下，宽是240，高是320！
    if (TOUCH_INV_X) final_x = 240 - final_x; 
    if (TOUCH_INV_Y) final_y = 320 - final_y;

    return (1 << 31) | (final_x << 16) | final_y;
}