-- ==============================================================================
-- Copyright (c) 2026 L2C Architect | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

local M = {}

-- ------------------------------------------
-- 🔀 映射 4：控制流生成器 (If / ElseIf / Else)
-- ------------------------------------------
function M:gen_if(node)
    
    -- 🔥 [L2C 终极净化]：探测并切除 Teal 偷偷注入的旧版 Lua 兼容垫片 (Polyfill)
    if node.if_blocks and node.if_blocks[1] and node.if_blocks[1].exp then
        local first_cond = self:gen(node.if_blocks[1].exp)
        if first_cond:match("_VERSION") then
            -- 🎯 [核心修复]：必须使用合法的 Nelua 注释语法 `--`，切忌使用 C 注释 `/* */`
            return "-- L2C: Stripped Teal Compat Polyfill"
        end
    end

    local out = {}
    
    -- 遍历所有的 if / elseif / else 块
    for i, block in ipairs(node.if_blocks) do
        if block.tk == "if" or block.tk == "elseif" then
            local cond = self:gen(block.exp)
            local prefix = (i == 1) and "if" or "elseif"
            table.insert(out, self:indent() .. prefix .. " " .. cond .. " then")
        elseif block.tk == "else" then
            table.insert(out, self:indent() .. "else")
        end
        
        -- 递归生成块内部的语句
        self.indent_level = self.indent_level + 1
        -- 因为内部通常是一个 statements 节点，这里直接去掉缩进插入，让 gen_statements 处理
        -- 但为了防止多余的换行，我们做一点优化拼接
        local body_str = self:gen(block.body)
        if body_str ~= "" then table.insert(out, body_str) end
        self.indent_level = self.indent_level - 1
    end
    
    table.insert(out, self:indent() .. "end")
    return table.concat(out, "\n")
end

-- 🎯 [探针闭环]：绝不瞎猜属性名，直接打印 while 节点的真实物理结构
function M:gen_while(node)
    -- 🎯 [真相] Teal 的循环条件就在 node.exp 里，绝无二处
    local condition = self:gen(node.exp)
    
    -- 🎯 [真相] 循环体在 node.body 里
    local body = self:gen(node.body)
    
    -- 拼装 Nelua
    local out = {}
    table.insert(out, string.format("while %s do", condition))
    table.insert(out, body)
    table.insert(out, self:indent() .. "end")
    
    return table.concat(out, "\n")
end

-- ------------------------------------------
-- 🔄 映射 5：循环生成器 (For-Loop 完美版)
-- ------------------------------------------
function M:gen_fornum(node)
    local out = {}
    
    local var_name = node.var.tk
    local start_exp = self:gen(node.from)
    local end_exp = self:gen(node.to)
    local step_exp = node.step and (", " .. self:gen(node.step)) or ""
    
    table.insert(out, self:indent() .. string.format("for %s = %s, %s%s do", var_name, start_exp, end_exp, step_exp))
    
    self.indent_level = self.indent_level + 1
    local body_str = self:gen(node.body)
    if body_str ~= "" then table.insert(out, body_str) end
    self.indent_level = self.indent_level - 1
    
    table.insert(out, self:indent() .. "end")
    return table.concat(out, "\n")
end

-- 🎯 [正规军底层闭环]：精准对齐 Teal AST 真实属性，彻底打通控制流
function M:gen_return(node)
    -- Teal AST 的返回值列表存放在 exps 属性中
    if node.exps then
        local exprs_str = self:gen(node.exps)
        -- 🛡️ 防御：如果解包出来是空字符串，说明是裸 return 或者是无需返回值的退出
        if exprs_str and exprs_str ~= "" then
            return "return " .. exprs_str
        end
    end
    
    return "return"
end

return M
