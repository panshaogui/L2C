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
