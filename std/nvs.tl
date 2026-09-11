-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- std/nvs.tl
-- L2C 0-GC 非易失性存储引擎 (NVS)
-- @l2c_source: clib/mcu/esp32_nvs.c
-- @l2c_import: std/lora_sx1262.tl

-- L2C FFI 探针 (注意：Teal 里的 string 会被我们的 IR 引擎自动安全降维成 C 语言的 const char*)
local type C_NVS = record
    l2c_nvs_init: function()
    l2c_nvs_get_int: function(string, integer): integer
    l2c_nvs_set_int: function(string, integer)
    l2c_nvs_set_stackstr: function(string, any): integer
    l2c_nvs_get_stackstr: function(string, any, integer): integer
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

-- [极速扰乱器] 翻转位域，把明文变成不会产生 \0 的乱码，对称加密！
local function NVS_Cipher_StackStr(str: any)
    local len = C_ESP_IDF.l2c_get_byte(str, 0)
    for i = 1, len do
        local c = C_ESP_IDF.l2c_get_byte(str, i)
        -- XOR 0x88 (136): 保证所有可见字符被踢到扩展 ASCII 区间
        C_ESP_IDF.l2c_set_byte(str, i, c ~ 0x88)
    end
end