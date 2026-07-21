-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- ==============================================================================
-- L2C 极简标准库：硬件级对称多处理 (SMP) 点火器
-- 警告：通过 Multicore_Launch 发射的函数，严禁闭包捕获！
-- ==============================================================================

local type C_MULTICORE = record
    l2c_launch_core1: function(any)
end

local type Multicore = record
end

-- @L2C_Inline: 发射业务函数到物理 Core 1
global function Multicore_Launch(task_func: any)
    C_MULTICORE.l2c_launch_core1(L2C_FuncPtr(task_func))
end
