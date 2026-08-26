-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

local M = {}
local IR = require("codegen.ir")

-- [L2C-LIR 引擎接入] 物理降维类型推导
local function build_type_ir(type_node)
    if not type_node then return IR.Type.Primitive("integer") end
    local t_name = type_node.typename or "any"
    if t_name == "nominal" and type_node.names and type_node.names[1] then
        return IR.Type.Primitive(type_node.names[1])
    end
    if t_name == "array" and type_node.elements then
        return IR.Type.Span(build_type_ir(type_node.elements))
    end
    if t_name == "string" then return IR.Type.Primitive("cstring") end
    if t_name == "any" then return IR.Type.Pointer() end
    if t_name == "function" then return IR.Type.Function() end
    return IR.Type.Primitive(t_name)
end

-- ------------------------------------------
--  映射 3：表赋值字面量生成器（无缝对接 C Stack Array）
-- ------------------------------------------
function M:gen_literal_table(node)
    -- 判断是否为合法的静态物理数组
    -- local is_array = node.expected and node.expected.typename == "array"
    local is_array = node.expected and (node.expected.typename == "array" or node.expected.typename == "tuple")
    
    if is_array then
        local elements = {}
        for _, item in ipairs(node) do
            if item.kind == "literal_table_item" then
                table.insert(elements, self:gen(item.value))
            end
        end
        -- [接入 LIR 引擎] 修复数组类型推导，确保 []string 被降维为 array of cstring
        local elem_ir = build_type_ir(node.expected.elements)
        local elem_type = elem_ir:to_nelua()

        --  [物理降维]：彻底封杀动态 Sequence！强制显式声明数组长度，
        -- 在 C 底层生成绝对安全的定长栈数组！例如 (@[256]number)
        return string.format("(@[%d]%s){%s}", #elements, elem_type, table.concat(elements, ", "))
    end
    
    local type_prefix = ""
    if node.expected and node.expected.typename == "nominal" and node.expected.names then
        type_prefix = node.expected.names[1]
    end
    
    --  [L2C 深度语义熔断]：既不是数组，也不是 Record。绝对是非法的动态 GC 表！
    if type_prefix == "" then
        self:panic("E001", node)
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

    return type_prefix .. "{" .. table.concat(out, ", ") .. "}"
end

--  [物理对齐]：转译字符串字面量节点（剥离双重引号）
function M:gen_string(node)
    local val = tostring(node.value or node.tk or node[1])
    
    -- [炸弹修复]：强制边界锚点，只有整个字符串完全是单个标识符时才触发枚举提取！
    -- 绝对不会再误伤 print("Hello STATE_BUY") 这样的业务日志或报错信息。
    local pure_val = val:match('^"([a-zA-Z_][a-zA-Z0-9_]*)"$') or val:match("^'([a-zA-Z_][a-zA-Z0-9_]*)'$")
    
    -- 如果在刚才写入的 enum_registry 找到了，立刻强转！
    if pure_val and self.enum_registry and self.enum_registry[pure_val] then
        local enum_name = self.enum_registry[pure_val]
        return enum_name .. "." .. pure_val
    end
    
    return val
end

function M:gen_integer(node) return node.tk end

--  [物理闭环]：精准转译布尔字面量（true / false）
function M:gen_boolean(node)
    return tostring(node.tk)
end

--  [类型拓荒]：打通浮点数 (float/double) 与 C 语言的映射
function M:gen_number(node)
    return tostring(node.tk or node.value)
end

--  [内存降维]：打通空指针 (nil)。在 C FFI 世界里，nil 必须物理映射为 nilptr (void* 0)
function M:gen_nil(node)
    return "nilptr"
end
return M
