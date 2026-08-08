-- ==============================================
-- 09_hls_counter.tl: L2C HLS 时序逻辑降维测试
-- ==============================================

-- 思想域：带记忆的硬件计数器 (注意 L2C_HDL_SEQ_ 前缀！)
-- 它的每一次运算都需要外部提供一个时钟上升沿信号 (Tick)
local function L2C_HDL_SEQ_Counter(step: integer): integer
    -- 声明一个带有记忆功能的寄存器 (D触发器)，复位初始值为 0
    local count = HDL_Reg(0)
    
    -- 在每一个时钟周期，将当前计数值与外部输入的 step 相加，塞回寄存器
    count = count + step
    
    -- 将寄存器的实时引脚状态连到输出总线
    return count
end

-- 物理域：随便留个入口防止报错
global function main(): integer
    print("Verilog Sequential HLS test...")
    return 0
end