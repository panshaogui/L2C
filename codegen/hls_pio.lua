-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- ==============================================================================
-- L2C HLS Engine: PIO State Machine Synthesizer
-- ==============================================================================

local HLS = {}

-- 把 AST 强转为 RP2040 .pio 汇编文本
function HLS.compile(func_node, engine)
    local out = {}
    
    -- 遍历函数体内的所有调用语句
    for _, stmt in ipairs(func_node.body or {}) do
        -- [核心拦截]：直接截获 label 节点，绕过 codegen/flow.lua 中的 nil bug
        if stmt.kind == "label" then
            -- 暴力兼容 Teal 各种版本，榨取 label 名称
            local label_name = stmt.name or stmt.label or (stmt.tk and type(stmt.tk) == "string" and stmt.tk) or "unknown_label"
            table.insert(out, label_name .. ":")
        else
            -- 复用 L2C 的 codegen，生成中间层文本，例如 "wait(0, gpio, 2)"
            local nelua_stmt = engine:gen(stmt)
            
            -- 利用正则剥离 Teal 函数调用的括号，降维成 PIO 汇编语法
            local fn, args_str = nelua_stmt:match("^([%w_]+)%((.*)%)$")
            
            if fn then
                -- 擦除 Teal 字符串字面量的引号（比如 jmp("loop") -> jmp loop）
                args_str = args_str:gsub('"', ''):gsub("'", "")
                
                -- PIO 汇编中，参数之间的逗号和空格是等价的，直接拼接
                if args_str == "" then
                    table.insert(out, "    " .. fn)
                else
                    -- 将多余的空格修正，保持原生 PIO 风格
                    args_str = args_str:gsub(",%s*", ", ")
                    table.insert(out, "    " .. fn .. " " .. args_str)
                end
            else
                -- 兜底：如果是未知表达式，直接原样保留（等待 pioasm 报错）
                table.insert(out, "    " .. nelua_stmt)
            end
        end
    end

    return table.concat(out, "\n")
end

return HLS
