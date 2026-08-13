-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- std/uv.tl
-- @l2c_link: uv
-- @l2c_include: uv.h

local type uv_loop_t = record end

local type C_UV = record
    uv_default_loop: function(): uv_loop_t
    -- uv_timer_t 本质是结构体，我们用 any 接收指针
    uv_timer_init: function(uv_loop_t, any): integer
    -- cb 回调函数直接声明为 any，底层映射为 C 的 void* 指针，无视签名障碍！
    uv_timer_start: function(any, any, integer, integer): integer
    uv_run: function(uv_loop_t, integer): integer
end

-- ==============================================================================
-- L2C 极简封装：Libuv 异步事件引擎
-- ==============================================================================

local function UV_DefaultLoop(): uv_loop_t
    return C_UV.uv_default_loop()
end

-- 接收指针 (timer_ptr)，直接透传给 C 引擎
local function UV_TimerInit(loop: uv_loop_t, timer_ptr: any): integer
    return C_UV.uv_timer_init(loop, timer_ptr)
end

-- 接收指针 (timer_ptr 和 cb_ptr)，直接透传！
local function UV_TimerStart(timer_ptr: any, cb_ptr: any, timeout: integer, repeat_ms: integer): integer
    return C_UV.uv_timer_start(timer_ptr, cb_ptr, timeout, repeat_ms)
end

local function UV_Run(loop: uv_loop_t): integer
    return C_UV.uv_run(loop, 0)
end