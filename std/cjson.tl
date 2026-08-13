-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- std/cjson.tl
-- @l2c_link: cjson
-- @l2c_include: cjson/cJSON.h

-- 1. 定义不透明指针 (底层映射为 void*)
local type cJSON_ptr = record end

-- 2. 挂载原生 C 函数 (严格对齐 C 标准头文件)
local type C_CJSON = record
    cJSON_Parse: function(any): cJSON_ptr
    cJSON_GetObjectItemCaseSensitive: function(cJSON_ptr, string): cJSON_ptr
    cJSON_IsNumber: function(cJSON_ptr): integer
    cJSON_IsString: function(cJSON_ptr): integer
    cJSON_GetNumberValue: function(cJSON_ptr): number
    cJSON_GetStringValue: function(cJSON_ptr): string
    cJSON_Delete: function(cJSON_ptr)
end

-- ==============================================================================
-- L2C 极简封装：CJSON 引擎
-- ==============================================================================

-- 路线 1：给高层应用使用 (解析 Lua 字符串，内部自动物理强转)
local function CJSON_ParseString(json_str: string): cJSON_ptr
    return C_CJSON.cJSON_Parse(L2C_Cast(json_str, "cstring"))
end

-- 路线 2：给高频网关使用 (直接传入 L2C_Ref 的网络缓冲区指针，0-GC 绝对零拷贝)
local function CJSON_ParseBuffer(buf_ptr: any): cJSON_ptr
    return C_CJSON.cJSON_Parse(buf_ptr)
end

local function CJSON_GetNumber(obj: cJSON_ptr, key: string): number
    local item = C_CJSON.cJSON_GetObjectItemCaseSensitive(obj, key)
    if item ~= nil and C_CJSON.cJSON_IsNumber(item) ~= 0 then
        return C_CJSON.cJSON_GetNumberValue(item)
    end
    return 0.0
end

local function CJSON_Free(obj: cJSON_ptr)
    if obj ~= nil then C_CJSON.cJSON_Delete(obj) end
end
