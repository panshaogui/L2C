-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- std/simdjson.tl
-- @l2c_link: simdjson
-- @l2c_source: clib/simdjson_wrapper.cpp
-- [补齐契约]：引入咱们的本地 C 语言头文件，补齐函数签名！
-- @l2c_include: clib/simdjson_wrapper.h

local type simd_ptr = record end

local type C_SIMD = record
    simdjson_c_parse: function(string, integer): simd_ptr
    simdjson_c_get_number: function(simd_ptr, string): number
    simdjson_c_free: function(simd_ptr)
end

-- ==============================================================================
-- L2C 极简封装：AVX-512 硬件加速 JSON 解析
-- ==============================================================================

local function SIMDJSON_Parse(json_str: string): simd_ptr
    -- 核心优雅：在底层自动计算字符串长度，无需用户干预
    return C_SIMD.simdjson_c_parse(json_str, #json_str)
end

local function SIMDJSON_GetNumber(obj: simd_ptr, key: string): number
    return C_SIMD.simdjson_c_get_number(obj, key)
end

local function SIMDJSON_Free(obj: simd_ptr)
    if obj ~= nil then 
        C_SIMD.simdjson_c_free(obj) 
    end
end
