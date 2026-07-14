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

-- 3. 极简封装，抛出给高层业务使用
local function cjson_parse(json_str: any): cJSON_ptr
    return C_CJSON.cJSON_Parse(json_str)
end

local function cjson_get_number(obj: cJSON_ptr, key: string): number
    local item = C_CJSON.cJSON_GetObjectItemCaseSensitive(obj, key)
    -- 🔥 恢复高层优雅：直接用 nil，底层引擎会帮我们映射为 nilptr！
    if item ~= nil and C_CJSON.cJSON_IsNumber(item) ~= 0 then
        return C_CJSON.cJSON_GetNumberValue(item)
    end
    return 0.0
end

local function cjson_free(obj: cJSON_ptr)
    -- 🔥 恢复高层优雅：直接用 nil
    if obj ~= nil then
        C_CJSON.cJSON_Delete(obj)
    end
end
