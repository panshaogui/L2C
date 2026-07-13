-- ==============================================================================
-- Copyright (c) 2026 L2C Architect | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- std/time.tl
-- @l2c_include: time.h

local type timespec = record
    tv_sec: integer
    tv_nsec: integer
end

-- 声明底层 C 原生命名空间
local type C_TIME = record
    clock_gettime: function(integer, any): integer
end

-- 1. 扁平化导出常量 (加前缀防冲突)
local TIME_CLOCK_REALTIME: integer = 0
local TIME_CLOCK_MONOTONIC: integer = 1

-- 2. 扁平化导出高层函数
-- 因为是物理拼接，你在外面的主策略文件里可以直接调用 time_now_ns()
local function time_now_ns(): integer
    local ts = L2C_Buffer(16) 
    C_TIME.clock_gettime(TIME_CLOCK_REALTIME, L2C_Ref(ts))
    
    -- (注意：这里目前返回 1000 是个占位，等咱们做了 Pydantic/Cast 之后再解包它！)
    return 1000 
end