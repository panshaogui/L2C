-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- @l2c_source: clib/mcu/esp32_ota.c
local type C_OTA = record
    l2c_ota_start: function(string): integer
end

global function OTA_Start(url: string)
    C_OTA.l2c_ota_start(url)
end