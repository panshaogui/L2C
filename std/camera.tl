-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- @l2c_source: clib/mcu/esp32_camera.c

local type C_CAM = record
    l2c_cam_init: function(): integer
    l2c_cam_get_frame: function(): any
    l2c_cam_get_frame_len: function(): integer 
    l2c_cam_return_frame: function(any)
    l2c_cam_set_dir: function(integer, integer)
    l2c_cam_init_jpeg: function(): integer
    l2c_cam_save_jpg: function(string): integer
    l2c_cam_get_pixels: function(any): any
end

global function Camera_Init(): boolean
    return C_CAM.l2c_cam_init() == 1
end

global function Camera_Capture(): any, integer
    local fb_ptr = C_CAM.l2c_cam_get_frame()
    local len = 0
    if L2C_PtrAsInt(fb_ptr) ~= 0 then
        len = C_CAM.l2c_cam_get_frame_len()
    end
    return fb_ptr, len
end

global function Camera_Release(fb_ptr: any)
    C_CAM.l2c_cam_return_frame(fb_ptr)
end

global function Camera_Set_Dir(hmirror: boolean, vflip: boolean)
    C_CAM.l2c_cam_set_dir(hmirror and 1 or 0, vflip and 1 or 0)
end

global function Camera_Init_JPEG(): boolean
    return C_CAM.l2c_cam_init_jpeg() == 1
end

global function Camera_Save_JPG(filepath: string): integer
    return C_CAM.l2c_cam_save_jpg(filepath)
end

global function Camera_Get_Pixels(fb_ptr: any): any
    return C_CAM.l2c_cam_get_pixels(fb_ptr)
end