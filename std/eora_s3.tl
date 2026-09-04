-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- std/eora_s3.tl
-- 亿佰特 EoRa-S3 (ESP32-S3) 隐藏物理引脚映射表

-- 定义 0-GC 的引脚物理结构
local type EoRa_Pins = record
    SCK: integer
    MISO: integer
    MOSI: integer
    CS: integer
    RST: integer
    BUSY: integer
    DIO1: integer

    SD_MISO: integer
    SD_MOSI: integer
    SD_SCK: integer
    SD_CS: integer
end

-- 静态实例化：将 Ebyte EoRa-S3 的隐藏布线硬编码锁死！
local EORA_BOARD: EoRa_Pins = {
    SCK = 5,
    MISO = 3,
    MOSI = 6,
    CS = 7,
    RST = 8,
    BUSY = 34,
    DIO1 = 33,
    
    SD_MISO = 2,
    SD_MOSI = 11,
    SD_SCK = 14,
    SD_CS = 13,
}

-- ESP-IDF GPIO 模式宏映射 (FFI 用)
local GPIO_MODE_INPUT: integer = 1
local GPIO_MODE_OUTPUT: integer = 2