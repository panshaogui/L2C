-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- @l2c_source: clib/mcu/esp32_lcd.c

local type C_LCD = record
    l2c_lcd_init: function(): integer
    -- l2c_lcd_draw_frame: function(any, integer, integer)
    -- l2c_lcd_draw_cam_frame: function(any)
    l2c_lcd_draw_cam_cropped: function(any)
    l2c_lcd_fill_color: function(integer, integer, integer)
    l2c_lcd_draw_rect: function(integer, integer, integer, integer, integer, integer, integer)
    l2c_lcd_set_dir: function(integer, integer, integer)
    l2c_lcd_draw_jpg_from_sd: function(string): integer
    l2c_lcd_draw_cam_cw90: function(any) -- [顺时针 90度探针]
end

global function LCD_Init(): boolean
    return C_LCD.l2c_lcd_init() == 1
end

global function LCD_Draw_Cam_Frame(fb_ptr: any)
    -- C_LCD.l2c_lcd_draw_cam_cw90(fb_ptr)
    -- 严丝合缝地对接摄像头的 320x240，硬件 DMA 会自动完成切轴！
    -- C_LCD.l2c_lcd_draw_frame(fb_ptr, 320, 240)
    -- C_LCD.l2c_lcd_draw_cam_frame(fb_ptr)
    C_LCD.l2c_lcd_draw_cam_cropped(fb_ptr)
end

global function LCD_Fill(r: integer, g: integer, b: integer)
    C_LCD.l2c_lcd_fill_color(r, g, b)
end

global function LCD_Draw_Rect(x: integer, y: integer, w: integer, h: integer, r: integer, g: integer, b: integer)
    C_LCD.l2c_lcd_draw_rect(x, y, w, h, r, g, b)
end

global function LCD_Set_Dir(swap_xy: boolean, mirror_x: boolean, mirror_y: boolean)
    C_LCD.l2c_lcd_set_dir(swap_xy and 1 or 0, mirror_x and 1 or 0, mirror_y and 1 or 0)
end

global function LCD_Draw_JPG_From_SD(filepath: string): integer
    return C_LCD.l2c_lcd_draw_jpg_from_sd(filepath)
end