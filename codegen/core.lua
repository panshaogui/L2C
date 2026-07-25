-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

local Codegen = {}
Codegen.__index = Codegen

local DIAG = require("codegen.diagnostics")

-- 映射 AST 节点到专属错误码
local AST_TO_E_CODE = {
    ["table"] = "E001",
    ["function"] = "E002",
    ["forin"] = "E003"
}

function Codegen.new(bundled_code, line_map)
    return setmetatable({ indent_level = 0, record_registry = {}, bundled_code = bundled_code, line_map = line_map or {} }, Codegen)
end

function Codegen:indent()
    return string.rep("  ", self.indent_level)
end

-- 动态挂载中心化的 Panic 熔断器 (Mixin 模式)
Codegen.panic = DIAG.panic

function Codegen:gen(node)
    --  [纯字符串拦截]：当节点直接退化为纯文本且命中大写 C 时，精准映射为小写 c
    if type(node) ~= "table" then 
        local str = tostring(node)
        if str == "C" then return "c" end
        return str 
    end
    
    if not node.kind and node[1] then
        local out = {}
        for _, v in ipairs(node) do table.insert(out, self:gen(v)) end
        return table.concat(out, ", ")
    end

    local kind = node.kind
    if not kind then return "" end

    -- [AST 第一道门控]
    if AST_TO_E_CODE[kind] then
        self:panic(AST_TO_E_CODE[kind], node)
    end

    local handler = self["gen_" .. kind]
    if handler then
        return handler(self, node)
    else
        self:panic("E099", node)
    end
end

-- ==========================================
--  核心处理器
-- ==========================================
function Codegen:gen_statements(node)
    local out = {}
    for _, stmt in ipairs(node) do table.insert(out, self:indent() .. self:gen(stmt)) end
    return table.concat(out, "\n")
end

-- [[ 显式混入：无任何性能开销，报错直接定位到具体文件的具体行 ]]
local function mixin(sub_table)
    for method, fn in pairs(sub_table) do
        Codegen[method] = fn
    end
end

mixin(require("codegen.declaration"))
mixin(require("codegen.expression"))
mixin(require("codegen.flow"))
mixin(require("codegen.identifier"))
mixin(require("codegen.literal"))

return Codegen

