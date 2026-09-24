-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- @l2c_source: clib/mcu/esp32_nuklear.c

local type C_NK = record
    l2c_nk_init: function(): integer
    l2c_nk_resize: function(integer, integer)
    l2c_nk_input: function(integer, integer, integer, integer)
    l2c_nk_render: function(integer, integer, integer)
    l2c_nk_begin: function(string, number, number, number, number): integer
    l2c_nk_end: function()
    l2c_nk_layout_row_dynamic: function(number, integer)
    l2c_nk_button_label: function(string): integer
    l2c_nk_label: function(string)
end

global function NK_Init(): boolean return C_NK.l2c_nk_init() == 1 end

-- [新增] 动态重置画板大小
global function NK_Resize(w: integer, h: integer) 
    C_NK.l2c_nk_resize(w, h) 
end

-- 增加了 y轴 偏移量防抖
global function NK_Input(pressed: boolean, x: integer, y: integer, offset_y: integer) 
    C_NK.l2c_nk_input(pressed and 1 or 0, x, y, offset_y) 
end

-- 增加了 坐标和宽高 定位
global function NK_Render(offset_y: integer, w: integer, h: integer) 
    C_NK.l2c_nk_render(offset_y, w, h) 
end

global function NK_Begin(title: string, x: number, y: number, w: number, h: number): boolean
    return C_NK.l2c_nk_begin(title, x, y, w, h) == 1
end
global function NK_End() C_NK.l2c_nk_end() end
global function NK_Layout_Row(height: number, cols: integer) C_NK.l2c_nk_layout_row_dynamic(height, cols) end
global function NK_Button(text: string): boolean return C_NK.l2c_nk_button_label(text) == 1 end
global function NK_Label(text: string) C_NK.l2c_nk_label(text) end