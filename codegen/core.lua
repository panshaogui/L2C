-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

local Codegen = {}
Codegen.__index = Codegen

--  [L2C 物理域绝对禁令清单]：只要触碰，直接引发架构级熔断！
local BANNED_AST_NODES = {
    ["table"] = "触发了动态表 (Table) 分配！这会引发严重的堆内存碎片与 GC 灾难。在 L2C 物理域中被严格禁止！请改用 L2C_Buffer 或静态 Record。",
    ["function_expr"] = "触发了匿名闭包 (Closure)！闭包会隐式捕获外部变量并引发堆内存分配。L2C 严格禁止！请在顶层声明纯静态函数并使用 L2C_FuncPtr 传递指针。",
    ["forin"] = "触发了泛型迭代器循环 (ipairs/pairs)！迭代器在底层依赖闭包状态机，会触发 GC。在 L2C 物理域中，请使用最硬核的数值循环 (for i=1, n do) 遍历物理内存！"
}

function Codegen.new()
    -- 显式初始化类型注册表，用来动态缓存所有的 Record 字段结构
    return setmetatable({ indent_level = 0, record_registry = {} }, Codegen)
end

function Codegen:indent()
    return string.rep("  ", self.indent_level)
end

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

    local handler = self["gen_" .. kind]
    if handler then
        return handler(self, node)
    else
        --  [AST 门控安检站]：对未知节点进行审判
        print("\n========================================================")
        if BANNED_AST_NODES[kind] then
            print(" [L2C 架构熔断] 触犯 0-GC 物理纪律: '" .. kind .. "' 节点")
            print("  -> 判决: " .. BANNED_AST_NODES[kind])
        else
            print(" [L2C 编译器提示] 遇到尚未支持的 AST 节点: '" .. kind .. "'")
            print("  -> 状态: 该节点可能是合法的无状态逻辑 (如 repeat, goto 等)。")
            print("  -> 行动: 引擎尚未对其支持。请在 codegen 模块中补充 `gen_" .. kind .. "` 方法！")
        end
        
        print("  ->  故障节点现场 Dump:")
        for k, v in pairs(node) do 
            if type(v) ~= "table" then print("      [" .. k .. "] = " .. tostring(v)) end 
        end
        print("========================================================\n")
        os.exit(1)
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

