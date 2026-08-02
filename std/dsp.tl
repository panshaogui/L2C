-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- std/dsp.tl
-- 专为 L2C 单片机打造的纯物理 0-GC 信号处理库 (Q15 极速定点数 & 纯物理指针版)
-- 浮点数 Goertzel 算法 (PC端调试用)
local function dsp_goertzel_mag(samples_ptr_int: integer, coeff: number, n: integer): number
    local s_prev = 0.0
    local s_prev2 = 0.0
    
    for i = 1, n do
        local val = L2C_ReadArray(samples_ptr_int, i - 1)
        local s = val + (coeff * s_prev) - s_prev2
        s_prev2 = s_prev
        s_prev = s
    end
    
    local power = (s_prev2 * s_prev2) + (s_prev * s_prev) - (coeff * s_prev * s_prev2)
    return power
end

-- Q15 Goertzel 算法：单周期乘加，零浮点开销，完美防溢出
-- samples_ptr_int: 物理波形内存地址 (经 L2C_PtrAsInt 强转的整数)
-- coeff_q15: 预先算好的目标频率系数 = round(2 * cos(2*pi*f/fs) * 32768)
-- n: 采样点数
local function dsp_goertzel_mag_q15(samples_ptr_int: integer, coeff_q15: integer, n: integer): integer
    local s_prev: integer = 0
    local s_prev2: integer = 0
    
    for i = 1, n do
        -- 1. C 语言级物理指针寻址，彻底碾压数组传参带来的 ABI 错乱与按值拷贝！
        local val = L2C_ReadArray(samples_ptr_int, i - 1)
        
        -- 2. 强制使用 // 32768，拒绝 C 语言对负数右移 >> 15 的未定义行为！
        local s = val + ((coeff_q15 * s_prev) // 32768) - s_prev2
        s_prev2 = s_prev
        s_prev = s
    end
    
    -- 最后的能量结算：在 64 位空间内展开，防止相乘溢出
    local p1 = s_prev2 * s_prev2
    local p2 = s_prev * s_prev
    local p3 = ((coeff_q15 * s_prev) // 32768) * s_prev2
    
    return p1 + p2 - p3
end