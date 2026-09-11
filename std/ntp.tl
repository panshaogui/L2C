-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- std/ntp.tl
-- L2C 0-GC NTP 网络时间引擎

-- @l2c_source: clib/mcu/esp32_ntp.c

local type C_NTP = record
    l2c_ntp_init: function()
    l2c_ntp_is_synced: function(): integer
    l2c_ntp_get_time_str: function(any)
end

local function NTP_init()
    C_NTP.l2c_ntp_init()
end

local function NTP_is_synced(): boolean
    return C_NTP.l2c_ntp_is_synced() == 1
end

local function NTP_get_time_str(ptr: any)
    C_NTP.l2c_ntp_get_time_str(ptr)
end