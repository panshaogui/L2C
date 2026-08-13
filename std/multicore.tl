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

-- 核心升级：强类型校验！参数不再是 any，而是必须为无参函数 function()！
-- 这样 Teal 前端会帮我们拦截错误的传参。
global function Multicore_Launch(task_func: function())
    -- 脏活掩盖：在这里自动将 Lua 函数强转为 C 物理指针！普通用户再也看不见它！
    C_MULTICORE.l2c_launch_core1(L2C_FuncPtr(task_func))
end
