-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- std/ble_nus.tl
-- L2C 0-GC 蓝牙透传控制台 (NimBLE NUS)
-- @l2c_source: clib/mcu/esp32_ble.c

local type C_BLE = record
    l2c_ble_init: function()
    l2c_ble_pop_char: function(): integer
end

local function BLE_init()
    C_BLE.l2c_ble_init()
end

local function BLE_pop_char(): integer
    return C_BLE.l2c_ble_pop_char()
end