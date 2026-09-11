-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- std/wifi.tl
-- L2C 0-GC 战术基站 WiFi 引擎

-- 物理挂载 C 源码
-- @l2c_source: clib/mcu/esp32_wifi.c

local type C_WIFI = record
    l2c_wifi_init_sta: function(string, string)
    l2c_wifi_is_connected: function(): integer
    l2c_wifi_get_ip_str: function(any)
end

local function WIFI_init_sta(ssid: string, pass: string)
    C_WIFI.l2c_wifi_init_sta(ssid, pass)
end

local function WIFI_is_connected(): boolean
    return C_WIFI.l2c_wifi_is_connected() == 1
end

local function WIFI_get_ip_str(ptr: any)
    C_WIFI.l2c_wifi_get_ip_str(ptr)
end