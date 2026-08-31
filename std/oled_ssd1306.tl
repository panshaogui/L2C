-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- std/oled_ssd1306.tl
-- L2C 0-GC 战术雷达副屏驱动 (SSD1306 I2C)

-- L2C FFI 探针
local type C_OLED = record
    l2c_oled_init: function(integer, integer)
    l2c_oled_print: function(integer, string)
    l2c_oled_print_num: function(integer, string, integer)
end

local function OLED_init(sda: integer, scl: integer)
    C_OLED.l2c_oled_init(sda, scl)
end

-- line: 0 ~ 7 (一共八行)
local function OLED_print(line: integer, txt: string)
    C_OLED.l2c_oled_print(line, txt)
end

local function OLED_print_num(line: integer, prefix: string, num: integer)
    C_OLED.l2c_oled_print_num(line, prefix, num)
end

-- 瞬间清空物理显存
local function OLED_clear()
    for i = 0, 7 do
        C_OLED.l2c_oled_print(i, "")
    end
end

local function OLED_clear_3to6()
    for i = 3, 6 do
        C_OLED.l2c_oled_print(i, "")
    end
end