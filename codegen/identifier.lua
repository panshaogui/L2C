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
    -- [接入 LIR 引擎] 彻底修复函数参数的 GC string 漏水问题
    local type_ir = build_type_ir(node.argtype)
    local type_name = type_ir:to_nelua()
    
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
