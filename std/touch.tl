-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- @l2c_source: clib/mcu/esp32_cst816.c

local type C_TOUCH = record
    l2c_touch_init: function(): integer
    l2c_touch_get_pos: function(): integer
end

global function Touch_Init(): boolean
    return C_TOUCH.l2c_touch_init() == 1
end

-- 返回: 是否按下, X坐标, Y坐标
global function Touch_Get(): boolean, integer, integer
    local val = C_TOUCH.l2c_touch_get_pos()
    if val == 0 then return false, 0, 0 end
    
    local x = (val >> 16) & 0x0FFF
    local y = val & 0x0FFF
    return true, x, y
end