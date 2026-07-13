-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- std/simdjson.tl
-- @l2c_link: simdjson
-- @l2c_source: clib/simdjson_wrapper.cpp
-- 🔥 [补齐契约]：引入咱们的本地 C 语言头文件，补齐函数签名！
-- @l2c_include: clib/simdjson_wrapper.h

local type simd_ptr = record end

local type C_SIMD = record
    simdjson_c_parse: function(string, integer): simd_ptr
    simdjson_c_get_number: function(simd_ptr, string): number
    simdjson_c_free: function(simd_ptr)
end

-- 高层优雅封装
local function simd_parse(json_str: string, len: integer): simd_ptr
    return C_SIMD.simdjson_c_parse(json_str, len)
end

local function simd_get_number(obj: simd_ptr, key: string): number
    return C_SIMD.simdjson_c_get_number(obj, key)
end

local function simd_free(obj: simd_ptr)
    if obj ~= nil then C_SIMD.simdjson_c_free(obj) end
end
