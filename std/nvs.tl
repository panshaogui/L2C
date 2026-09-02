-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- std/nvs.tl
-- L2C 0-GC 非易失性存储引擎 (NVS)
-- @l2c_source: clib/mcu/esp32_nvs.c

-- L2C FFI 探针 (注意：Teal 里的 string 会被我们的 IR 引擎自动安全降维成 C 语言的 const char*)
local type C_NVS = record
    l2c_nvs_init: function()
    l2c_nvs_get_int: function(string, integer): integer
    l2c_nvs_set_int: function(string, integer)
end

local function NVS_init()
    C_NVS.l2c_nvs_init()
end

local function NVS_get_int(key: string, default_val: integer): integer
    return C_NVS.l2c_nvs_get_int(key, default_val)
end

local function NVS_set_int(key: string, val: integer)
    C_NVS.l2c_nvs_set_int(key, val)
end