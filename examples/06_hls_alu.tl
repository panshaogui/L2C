-- ==============================================
-- 06_hls_alu.tl: L2C HLS 到 Verilog 组合逻辑降维测试
-- ==============================================

-- 思想域：高频交易中的快速价格掩码组合逻辑
-- (在硬件电路中，没有分支，所有操作都在 1 个时钟周期内极速流转)
local function L2C_HDL_PriceMask(price: integer, threshold: integer, ctrl: integer): integer
    -- 计算价差 (硬件全加器)
    local diff = price - threshold
    
    -- 位运算生成特征 (硬件逻辑门)
    local mask_a = diff & 0x0000FFFF
    local mask_b = price | ctrl

    -- 核心修复：在 Lua 中，按位异或是 ~ 符号！
    local result = mask_a ~ mask_b
    return result
end

-- 物理域：随便留个入口防止报错
global function main(): integer
    print("Verilog HLS Transpilation test...")
    return 0
end