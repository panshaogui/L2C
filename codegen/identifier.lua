-- ==============================================================================
-- Copyright (c) 2026 L2C Architect | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

local M = {}

-- 🎯 [正规军闭环]：转译变量节点，精准降维打击 FFI 空间的游民符号
function M:gen_variable(node)
    -- 如果变量标记是大写 C，直接优雅归化为小写 c，打通 FFI 伪命名空间
    -- 🔥 拦截所有 C_ 开头或纯 C 的伪命名空间，降维至小写 c
    if node.tk == "C" or node.tk:match("^C_") then
        return "c"
    end
    
    -- 正常的其他所有业务变量（如 tick, bid_qty），原封不动返回原文
    return node.tk
end

function M:gen_identifier(node)
    local name = node.tk

    -- 🎯 [类型安全检查]：检查当前节点的 typeid 是否记录在我们的 FFI 白皮书中
    if node.typeid and self.ffi_typeids and self.ffi_typeids[node.typeid] then
        -- 如果命中，优雅映射为 Nelua 的原生伪命名空间 c
        return "c"
    end
    
    -- 正常业务变量，安全过闸
    return name
end

-- 🎯 [物理闭环]：转译函数参数节点 (变量名: 类型)
function M:gen_argument(node)
    local arg_name = node.tk
    local type_name = "integer" -- 兜底默认类型
    
    -- 从 Teal 标称类型对象的 names 数组中精准提取类型字符串
    if node.argtype and node.argtype.names and node.argtype.names[1] then
        type_name = node.argtype.names[1]
    end
    
    -- 拼装成标准的 Nelua 原生参数声明 (tick: BookTick)
    return string.format("%s: %s", arg_name, type_name)
end

function M:gen_argument_list(node)
    -- argument_list 本身是一个数组包裹的参数节点
    local out = {}
    for _, arg in ipairs(node) do
        table.insert(out, self:gen(arg))
    end
    return table.concat(out, ", ")
end

function M:gen_expression_list(node)
    local out = {}
    for _, v in ipairs(node) do table.insert(out, self:gen(v)) end
    return table.concat(out, ", ")
end

M.gen_variable_list = M.gen_expression_list

-- 🎯 [物理闭环]：转译类型标识符节点
function M:gen_type_identifier(node)
    return node.tk
end

return M
