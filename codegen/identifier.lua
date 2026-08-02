-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

local M = {}

--  [正规军闭环]：转译变量节点，精准降维打击 FFI 空间的游民符号
function M:gen_variable(node)
    return node.tk
end

function M:gen_identifier(node)
    return node.tk
end

--  [物理闭环]：转译函数参数节点 (变量名: 类型)
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

--  [物理闭环]：转译类型标识符节点
function M:gen_type_identifier(node)
    return node.tk
end

return M
