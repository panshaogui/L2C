-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- ==============================================================================
-- L2C HLS Engine: Verilog RTL Synthesizer (Combinatorial & Sequential Logic)
-- ==============================================================================
local HLS = {}

local function translate_op(expr)
    expr = expr:gsub("//", "/")
    expr = expr:gsub(" ~ ", " ^ ")
    expr = expr:gsub("0x(%x+)", "32'h%1")
    return expr
end

function HLS.compile(func_node, engine)
    local raw_name = func_node.name and func_node.name.tk or "Unknown"
    local mod_name = raw_name:gsub("^L2C_HDL_", "")
    
    -- [核心魔法]：嗅探 SEQ_ 前缀，判定是否为时序逻辑电路
    local is_seq = mod_name:match("^SEQ_")
    
    local out = {}
    table.insert(out, "module " .. mod_name .. "(")

    local ports = {}
    -- 时序电路必须注入全局时钟 (clk) 和低电平复位 (rst_n)
    if is_seq then
        table.insert(ports, "    input wire clk")
        table.insert(ports, "    input wire rst_n")
    end
    
    for _, arg in ipairs(func_node.args or {}) do
        if arg.kind == "argument" then
            table.insert(ports, "    input wire [31:0] " .. arg.tk)
        end
    end
    table.insert(ports, "    output wire [31:0] out_0")

    table.insert(out, table.concat(ports, ",\n"))
    table.insert(out, ");\n")

    local always_body = {}
    local resets = {}

    for _, stmt in ipairs(func_node.body or {}) do
        local text = translate_op(engine:gen(stmt))
        
        -- 模式 1: 硬件寄存器 (D触发器) -> local count = HDL_Reg(0)
        local reg_var, init_val = text:match("^local%s+([%w_]+)%s*=%s*HDL_Reg%(([^%)]+)%)")
        
        -- 模式 2: 普通连线 -> local mask = a & b
        local wire_var, wire_expr = text:match("^local%s+([%w_]+)%s*=%s*(.*)$")
        
        -- 模式 3: 输出连线 -> return count
        local ret_expr = text:match("^return%s+(.*)$")
        
        -- 模式 4: 赋值操作 -> count = count + step
        local assign_var, assign_expr = text:match("^([%w_]+)%s*=%s*(.*)$")

        if reg_var then
            -- 声明寄存器，并加入复位列表
            table.insert(out, "    reg [31:0] " .. reg_var .. ";")
            table.insert(resets, "            " .. reg_var .. " <= " .. init_val .. ";")
        elseif wire_var then
            table.insert(out, "    wire [31:0] " .. wire_var .. ";")
            table.insert(out, "    assign " .. wire_var .. " = " .. wire_expr .. ";")
        elseif ret_expr then
            table.insert(out, "    assign out_0 = " .. ret_expr .. ";")
        elseif assign_var and assign_expr then
            if is_seq then
                -- 时序逻辑：使用非阻塞赋值 (<=) 并放入 always 块
                table.insert(always_body, "            " .. assign_var .. " <= " .. assign_expr .. ";")
            else
                -- 组合逻辑：直接连续赋值
                table.insert(out, "    assign " .. assign_var .. " = " .. assign_expr .. ";")
            end
        end
    end

    -- 物理织入：生成同步时钟块
    if is_seq then
        table.insert(out, "\n    always @(posedge clk or negedge rst_n) begin")
        table.insert(out, "        if (!rst_n) begin")
        for _, r in ipairs(resets) do table.insert(out, r) end
        table.insert(out, "        end else begin")
        for _, a in ipairs(always_body) do table.insert(out, a) end
        table.insert(out, "        end")
        table.insert(out, "    end")
    end

    table.insert(out, "endmodule\n")
    return table.concat(out, "\n")
end

return HLS
