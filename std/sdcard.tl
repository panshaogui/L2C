-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- std/sdcard.tl
-- L2C 0-GC 战术黑匣子 (TF/MicroSD 驱动)
-- @l2c_source: clib/mcu/esp32_sdcard.c

local type C_SDCARD = record
    l2c_sdcard_init: function(integer, integer, integer, integer): integer
    l2c_sdcard_append: function(string, string)
end

local function SDCard_init(miso: integer, mosi: integer, sck: integer, cs: integer): boolean
    local res = C_SDCARD.l2c_sdcard_init(miso, mosi, sck, cs)
    if res == 0 then return true else return false end
end

local function SDCard_append(filename: string, text: string)
    C_SDCARD.l2c_sdcard_append(filename, text)
end