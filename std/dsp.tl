-- ==============================================================================
-- Copyright (c) 2026 L2C Architect | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- std/dsp.tl
-- 专为 L2C 单片机打造的纯物理 0-GC 信号处理库

-- 🔥 Goertzel 算法：以极低的 CPU 消耗，侦测指定频点的绝对能量！
-- samples: 传入的波形内存指针 (256个点)
-- coeff: 预先算好的目标频率系数
-- n: 采样点数
local function dsp_goertzel_mag(samples: {number}, coeff: number, n: integer): number
    local s_prev = 0.0
    local s_prev2 = 0.0
    
    for i = 1, n do
        local s = samples[i] + (coeff * s_prev) - s_prev2
        s_prev2 = s_prev
        s_prev = s
    end
    
    -- 计算该频率点的能量平方 (我们不需要开根号，直接比能量大小更省 CPU)
    local power = (s_prev2 * s_prev2) + (s_prev * s_prev) - (coeff * s_prev * s_prev2)
    return power
end
