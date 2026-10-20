-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- L2C HLS Engine: Verilog RTL Synthesizer (AST-Native Edition)
-- 彻底抛弃正则匹配，全链路基于 Teal AST 树物理降维！
local HLS = {}

local function get_wire_decl(t_name)
    if t_name == "bit" then return "" end
    if t_name == "uint3" then return "[2:0] " end
    if t_name == "uint8" then return "[7:0] " end
    if t_name == "uint10" then return "[9:0] " end
    if t_name == "uint16" then return "[15:0] " end
    return "[31:0] "
end

local function get_teal_type_name(t_node)
    if not t_node then return "integer" end
    if type(t_node) == "string" then return t_node end
    if t_node.typename == "nominal" and t_node.names and t_node.names[1] then
        return type(t_node.names[1]) == "table" and t_node.names[1].tk or t_node.names[1]
    end
    return t_node.tk or (t_node[1] and type(t_node[1]) == "string" and t_node[1]) or t_node.typename or "integer"
end

-- ============================================================================
-- [L2C V3 终极引擎] 全 AST 递归遍历器 (0% 正则，100% 精准)
-- ============================================================================
local V = {}
function V.gen_exp(node)
    if not node then return "" end
    if type(node) == "string" then return node end
    if node.kind == "variable" or node.kind == "identifier" then return node.tk end
    if node.kind == "integer" or node.kind == "number" then return tostring(node.tk or node.value) end
    if node.kind == "boolean" then return node.tk == "true" and "1'b1" or "1'b0" end
    -- 智能剥离字符串字面量的引号，供黑盒端口映射使用
    if node.kind == "string" then return tostring(node.tk or node.value):gsub('^["\']', ''):gsub('["\']$', '') end
    if node.kind == "paren" then return "(" .. V.gen_exp(node.e1 or node[1]) .. ")" end
    
    if node.kind == "op" then
        local op = node.op and node.op.op or node.op
        if op == "as" then return V.gen_exp(node.e1) end -- 硬件自动对齐，无视转型
        if op == "@funcall" or op == "call" then
            local fn = V.gen_exp(node.e1)
            if fn == "HDL_BRAM_Read" then return V.gen_exp(node.e2[1]) .. "[" .. V.gen_exp(node.e2[2]) .. "]" end
            return fn
        end
        
        if op == "and" then op = "&&" end
        if op == "or" then op = "||" end
        if op == "~=" or op == "!=" then op = "!=" end
        if op == "==" then op = "==" end
        if op == "//" then op = "/" end
        
        if node.e2 == nil then
            if op == "not" then return "!" .. V.gen_exp(node.e1) end
            if op == "~" then return "~" .. V.gen_exp(node.e1) end
            if op == "-" then return "-" .. V.gen_exp(node.e1) end
            return op .. V.gen_exp(node.e1)
        else
            if op == "~" then op = "^" end -- Teal 的位异或是 ~, Verilog 是 ^
            return V.gen_exp(node.e1) .. " " .. op .. " " .. V.gen_exp(node.e2)
        end
    end
    if node.kind == "index" then return V.gen_exp(node.e1) .. "[" .. V.gen_exp(node.e2) .. "]" end
    return "/*?*/"
end

function V.gen_stmt(node, indent)
    local out = {}
    local ind = string.rep("    ", indent)
    
    if node.kind == "assignment" then
        local lhs = V.gen_exp(node.vars[1] or node.vars)
        local rhs = V.gen_exp(node.exps[1] or node.exps)
        return ind .. lhs .. " <= " .. rhs .. ";"
    end
    
    if (node.kind == "op" and node.op.op == "@funcall") or node.kind == "call" then
        local fn = V.gen_exp(node.e1)
        if fn == "HDL_BRAM_Write" then
            return ind .. V.gen_exp(node.e2[1]) .. "[" .. V.gen_exp(node.e2[2]) .. "] <= " .. V.gen_exp(node.e2[3]) .. ";"
        end
    end
    
    if node.kind == "if" then
        for i, block in ipairs(node.if_blocks) do
            if block.tk == "if" or block.tk == "elseif" then
                local pfx = (i == 1) and "if" or "else if"
                table.insert(out, ind .. pfx .. " (" .. V.gen_exp(block.exp) .. ") begin")
            else
                table.insert(out, ind .. "else begin")
            end
            for _, s in ipairs(block.body or {}) do
                local s_str = V.gen_stmt(s, indent + 1)
                if s_str ~= "" then table.insert(out, s_str) end
            end
            table.insert(out, ind .. "end")
        end
        return table.concat(out, "\n")
    end
    return ""
end

function V.gen_top_stmt(node, is_seq, always_body, resets)
    if node.kind == "return" then
        local ret_exp = V.gen_exp(node.exps and node.exps[1])
        if ret_exp and ret_exp ~= "" then return "    assign out_0 = " .. ret_exp .. ";" end
        return ""
    end

    if node.kind == "assignment" then
        local lhs = V.gen_exp(node.vars[1] or node.vars)
        local rhs = V.gen_exp(node.exps[1] or node.exps)
        if is_seq then table.insert(always_body, "            " .. lhs .. " <= " .. rhs .. ";"); return ""
        else return "    assign " .. lhs .. " = " .. rhs .. ";" end
    end

    if (node.kind == "op" and node.op.op == "@funcall") or node.kind == "call" then
        local fn = V.gen_exp(node.e1)
        if fn == "HDL_Instance" then
            local m = V.gen_exp(node.e2[1])
            local inst = V.gen_exp(node.e2[2])
            local ports = V.gen_exp(node.e2[3])
            return "    " .. m .. " " .. inst .. " (" .. ports .. ");"
        elseif fn == "HDL_BRAM_Write" and is_seq then
            table.insert(always_body, "            " .. V.gen_exp(node.e2[1]) .. "[" .. V.gen_exp(node.e2[2]) .. "] <= " .. V.gen_exp(node.e2[3]) .. ";")
            return ""
        end
    end

    if node.kind == "local_declaration" or node.kind == "local" or (node.vars and node.exps) then
        local var_name = V.gen_exp(node.vars[1])
        local exp_node = node.exps and node.exps[1]
        
        if exp_node and ((exp_node.kind == "op" and exp_node.op.op == "@funcall") or exp_node.kind == "call") then
            local fn = V.gen_exp(exp_node.e1)
            if fn == "HDL_Wire" then
                local w = tonumber(V.gen_exp(exp_node.e2[1])) or 1
                local w_str = w > 1 and string.format("[%d:0] ", w - 1) or ""
                return "    wire " .. w_str .. var_name .. ";"
            elseif fn == "HDL_BRAM" then
                local bw = tonumber(V.gen_exp(exp_node.e2[1])) or 8
                local bd = tonumber(V.gen_exp(exp_node.e2[2])) or 1024
                return string.format("    reg [%d:0] %s [0:%d];", bw - 1, var_name, bd - 1)
            elseif fn == "HDL_Reg" then
                local init_val = V.gen_exp(exp_node.e2[1])
                local w_val = exp_node.e2[2] and tonumber(V.gen_exp(exp_node.e2[2])) or 32
                local w_str = w_val > 1 and string.format("[%d:0] ", w_val - 1) or ""
                table.insert(resets, "            " .. var_name .. " <= " .. init_val .. ";")
                return "    reg " .. w_str .. var_name .. ";"
            end
        end
        
        if exp_node then
            local rhs = V.gen_exp(exp_node)
            return "    wire [31:0] " .. var_name .. ";\n    assign " .. var_name .. " = " .. rhs .. ";"
        else
            return "    wire [31:0] " .. var_name .. ";"
        end
    end

    return ""
end
-- ============================================================================

function HLS.compile(func_node, engine)
    local raw_name = func_node.name and func_node.name.tk or "Unknown"
    local mod_name = raw_name:gsub("^L2C_HDL_", "")
    local is_seq = mod_name:match("^SEQ_")
    
    local out = {}
    table.insert(out, "module " .. mod_name .. "(")

    local ports = {}
    if is_seq then
        table.insert(ports, "    input wire clk")
        table.insert(ports, "    input wire rst_n")
    end
    
    for _, arg in ipairs(func_node.args or {}) do
        -- [核心修复] 只有在 is_seq 自动注入时才屏蔽，自定义架构必须放行 clk 和 rst_n！
        if arg.kind == "argument" and not (is_seq and (arg.tk == "clk" or arg.tk == "rst_n")) then
            local t_name = get_teal_type_name(arg.argtype)
            if arg.tk:match("^out_") then
                table.insert(ports, "    output wire " .. get_wire_decl(t_name) .. arg.tk)
            else
                table.insert(ports, "    input wire " .. get_wire_decl(t_name) .. arg.tk)
            end
        end
    end

    local ret_node = func_node.rets and func_node.rets.tuple and func_node.rets.tuple[1] or (func_node.rets and func_node.rets[1])
    local ret_type = get_teal_type_name(ret_node)
    table.insert(ports, "    output wire " .. get_wire_decl(ret_type) .. "out_0")

    table.insert(out, table.concat(ports, ",\n"))
    table.insert(out, ");\n")

    local always_body = {}
    local resets = {}
    local ast_clock_domains = {}
    local top_stmts = {}

    for _, stmt in ipairs(func_node.body or {}) do
        local is_clock_domain = false
        if stmt.kind == "if" and stmt.if_blocks and stmt.if_blocks[1] then
            local exp = stmt.if_blocks[1].exp
            if exp and (exp.kind == "op" or exp.kind == "call") then
                local op_val = exp.op and exp.op.op or exp.op
                if op_val == "@funcall" or exp.kind == "call" then
                    local fn_name = V.gen_exp(exp.e1)
                    if fn_name == "HDL_Clock_Domain" then
                        is_clock_domain = true
                        local clk = V.gen_exp(exp.e2[1])
                        local rst = exp.e2[2] and V.gen_exp(exp.e2[2]) or nil
                        local sensitivity = "posedge " .. clk
                        if rst and rst ~= "/*?*/" and rst ~= "" then sensitivity = sensitivity .. " or negedge " .. rst end
                        
                        table.insert(ast_clock_domains, "\n    always @(" .. sensitivity .. ") begin")
                        for _, s in ipairs(stmt.if_blocks[1].body or {}) do
                            local s_str = V.gen_stmt(s, 2)
                            if s_str ~= "" then table.insert(ast_clock_domains, s_str) end
                        end
                        table.insert(ast_clock_domains, "    end")
                    end
                end
            end
        end
        
        if not is_clock_domain then 
            local top_str = V.gen_top_stmt(stmt, is_seq, always_body, resets)
            if top_str ~= "" then table.insert(top_stmts, top_str) end
        end
    end

    for _, s in ipairs(top_stmts) do table.insert(out, s) end

    if is_seq then
        table.insert(out, "\n    always @(posedge clk or negedge rst_n) begin")
        table.insert(out, "        if (!rst_n) begin")
        for _, r in ipairs(resets) do table.insert(out, r) end
        table.insert(out, "        end else begin")
        for _, a in ipairs(always_body) do table.insert(out, a) end
        table.insert(out, "        end")
        table.insert(out, "    end")
    end

    for _, s in ipairs(ast_clock_domains) do table.insert(out, s) end

    table.insert(out, "endmodule\n")
    return table.concat(out, "\n")
end

return HLS