-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

local M = {}

-- ------------------------------------------
-- 🔥 映射 3：表赋值字面量生成器（无缝对接 C Stack Array）
-- ------------------------------------------
function M:gen_literal_table(node)
    local is_array = node.expected and node.expected.typename == "array"
    
    if is_array then
        local elements = {}
        for _, item in ipairs(node) do
            if item.kind == "literal_table_item" then
                table.insert(elements, self:gen(item.value))
            end
        end
        local elem_type = "integer"
        if node.expected.elements and node.expected.elements.typename then
            elem_type = node.expected.elements.typename
        end
        -- 🔥 [物理降维]：彻底封杀动态 Sequence！强制显式声明数组长度，
        -- 在 C 底层生成绝对安全的定长栈数组！例如 (@[256]number)
        return string.format("(@[%d]%s){%s}", #elements, elem_type, table.concat(elements, ", "))
    end

    -- 结构体(Record)的生成逻辑保持不变
    local out = {}
    for _, item in ipairs(node) do
        if item.kind == "literal_table_item" and item.tk then
            local k = item.tk
            local v = self:gen(item.value)
            table.insert(out, k .. " = " .. v)
        end
    end
    
    local type_prefix = ""
    if node.expected and node.expected.typename == "nominal" and node.expected.names then
        type_prefix = node.expected.names[1]
    end
    return type_prefix .. "{" .. table.concat(out, ", ") .. "}"
end

-- 🎯 [物理对齐]：转译字符串字面量节点（剥离双重引号）
function M:gen_string(node)
    -- Teal 节点带回来的 node.value 已经是包含双引号的干净字符串了，直接返回即可
    return tostring(node.value or node.tk or node[1])
end

function M:gen_integer(node) return node.tk end

-- 🎯 [物理闭环]：精准转译布尔字面量（true / false）
function M:gen_boolean(node)
    return tostring(node.tk)
end

-- 🔥 [类型拓荒]：打通浮点数 (float/double) 与 C 语言的映射
function M:gen_number(node)
    return tostring(node.tk or node.value)
end

-- 🔥 [内存降维]：打通空指针 (nil)。在 C FFI 世界里，nil 必须物理映射为 nilptr (void* 0)
function M:gen_nil(node)
    return "nilptr"
end
return M
