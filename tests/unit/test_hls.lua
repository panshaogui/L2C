-- ==============================================================================
-- L2C Unit Test: HLS Engines (PIO 状态机与 Verilog 综合器白盒测试)
-- [V3 终极引擎版] 全 AST 节点物理打击测试
-- ==============================================================================
local hls_pio = require("codegen.hls_pio")
local hls_verilog = require("codegen.hls_verilog")

print("[UNIT] 正在测试 HLS 综合器官 (PIO & Verilog) ...")

-- Mock Engine (仅供 PIO 老正则模块使用)
local mock_engine = {
    gen = function(self, stmt)
        return stmt.mock_text or ""
    end
}

-- ==========================================
--  战术测试 1: PIO 状态机综合测试 (保留正则脱壳)
-- ==========================================
local mock_pio_ast = {
    body = {
        { mock_text = 'set("pins", "1 [1]")' },
        { kind = "label", name = "delay_loop" },
        { mock_text = 'jmp("x--", "delay_loop")' }
    }
}

local pio_asm = hls_pio.compile(mock_pio_ast, mock_engine)
assert(pio_asm:match("set pins, 1 %[1%]"), " PIO 综合失败：脱壳机制失效 (set pins)")
assert(pio_asm:match("delay_loop:"), " PIO 综合失败：标签节点无法正常转化为硬件 Label")
assert(pio_asm:match("jmp x%-%-, delay_loop"), " PIO 综合失败：跳跃指令参数解析异常")

-- ==========================================
--  战术测试 2: Verilog 组合逻辑 (ALU) 测试 (全 AST 模拟)
-- ==========================================
local mock_alu_ast = {
    name = { tk = "L2C_HDL_ALU" },
    args = { { kind = "argument", tk = "a" }, { kind = "argument", tk = "b" } },
    body = {
        -- local x = a & b
        { kind = "local_declaration", vars = {{kind="variable", tk="x"}}, exps = {{kind="op", op="&", e1={kind="variable", tk="a"}, e2={kind="variable", tk="b"}}} },
        -- local y = a ~ b
        { kind = "local_declaration", vars = {{kind="variable", tk="y"}}, exps = {{kind="op", op="~", e1={kind="variable", tk="a"}, e2={kind="variable", tk="b"}}} },
        -- return x | y
        { kind = "return", exps = {{kind="op", op="|", e1={kind="variable", tk="x"}, e2={kind="variable", tk="y"}}} }
    }
}

local v_alu = hls_verilog.compile(mock_alu_ast, mock_engine)
assert(v_alu:match("module ALU%("), " Verilog 综合失败：模块名提取错误")
assert(v_alu:match("input wire %[31:0%] a"), " Verilog 综合失败：输入引脚 Input Port 丢失")
assert(v_alu:match("wire %[31:0%] x;"), " Verilog 综合失败：wire 声明被吞")
assert(v_alu:match("assign y = a %^ b;"), " Verilog 综合失败：Lua 的 ~ 没有被成功翻译为 Verilog 的 ^")
assert(v_alu:match("assign out_0 = x %| y;"), " Verilog 综合失败：返回值映射 out_0 失败")

-- ==========================================
--  战术测试 3: Verilog 时序逻辑 (Sequential) 测试 (全 AST 模拟)
-- ==========================================
local mock_seq_ast = {
    name = { tk = "L2C_HDL_SEQ_Counter" },
    args = { { kind = "argument", tk = "step" } },
    body = {
        -- local count = HDL_Reg(0)
        { kind = "local_declaration", vars = {{kind="variable", tk="count"}}, exps = {{kind="call", e1={kind="variable", tk="HDL_Reg"}, e2={{kind="integer", tk="0"}}}} },
        -- count = count + step
        { kind = "assignment", vars = {{kind="variable", tk="count"}}, exps = {{kind="op", op="+", e1={kind="variable", tk="count"}, e2={kind="variable", tk="step"}}} }
    }
}

local v_seq = hls_verilog.compile(mock_seq_ast, mock_engine)
assert(v_seq:match("input wire clk"), " Verilog 时序失败：缺失 clk 物理时钟引脚")
assert(v_seq:match("input wire rst_n"), " Verilog 时序失败：缺失 rst_n 复位引脚")
assert(v_seq:match("reg %[31:0%] count;"), " Verilog 时序失败：HDL_Reg 未能正确映射为 reg 寄存器")
assert(v_seq:match("always @%(posedge clk or negedge rst_n%)"), " Verilog 时序失败：缺失时钟触发 block")
assert(v_seq:match("count <= 0;"), " Verilog 时序失败：缺失非阻塞复位逻辑")
assert(v_seq:match("count <= count %+ step;"), " Verilog 时序失败：状态更新非阻塞赋值 (<=) 丢失")

print("[UNIT] HLS 器官 (PIO / Verilog 组合 / Verilog 时序) 语法降维与 AST 转换极致精准！")