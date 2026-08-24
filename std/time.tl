-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- std/time.tl
-- @l2c_include: time.h

local type timespec_t = record
    tv_sec: integer
    tv_nsec: integer
    -- 补上魔法签证，允许将底层栈内存强转为 timespec
    _cast: function(any): timespec_t
end

-- 声明底层 C 原生命名空间
local type C_TIME_TYPE = record
    clock_gettime: function(integer, any): integer
    
    -- 神级 C FFI：直接把 C 语言头文件里的宏常量作为变量引入！
    -- L2C 在底层会自动为它打上 <cimport('CLOCK_MONOTONIC'), nodecl> 的烙印
    -- 由 Clang/GCC 去决定它到底是 1(Linux) 还是 4(Mac)！
    CLOCK_MONOTONIC: integer
    CLOCK_REALTIME: integer
end

local C_TIME: C_TIME_TYPE

-- ==============================================================================
-- L2C 极简封装：纳秒级高精度物理时钟
-- ==============================================================================

-- 获取单调递增的纳秒时间戳 (免疫 NTP 授时跳变，专为 Benchmark 测距打造)
local function time_now_ns(): integer
    -- 在 C 函数栈上瞬间开辟 16 字节
    local ts_buf = L2C_Buffer(16) 
    
    -- 传入跨平台的宏常量和缓冲区的绝对物理地址
    C_TIME.clock_gettime(C_TIME.CLOCK_MONOTONIC, L2C_Ref(ts_buf))
    
    -- 0-GC 物理内存解包：直接把这块栈内存强转为 timespec 结构体
    local ts = timespec_t._cast(L2C_Ref(ts_buf))
    
    -- 计算绝对纳秒数 (1秒 = 10^9纳秒)
    return (ts.tv_sec * 1000000000) + ts.tv_nsec
end