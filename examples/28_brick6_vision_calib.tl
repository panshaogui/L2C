-- examples/28_brick6_vision_calib.tl
-- @l2c_import: std/camera.tl
-- @l2c_import: std/touch.tl
-- @l2c_import: std/lcd.tl

local type C_OS = record
    vTaskDelay: function(integer)
end

print("\n============================================")
print("  [砖块 6] 终极视觉矩阵标定仪 (32相穷举版)")
print("============================================\n")

LCD_Init()
Camera_Init()
Touch_Init()

-- 0 到 31，共 32 种组合
local mode = 0
local last_touched = false

local function Apply_Calibration()
    -- 取模运算：低 3 位控制 LCD (0~7)，高 2 位控制 Camera (0~3)
    local lcd_mode = mode % 8
    local cam_mode = mode // 8

    -- 1. 解析 LCD 状态
    local lcd_swap   = (lcd_mode & 4) == 4
    local lcd_mir_x  = (lcd_mode & 2) == 2
    local lcd_mir_y  = (lcd_mode & 1) == 1
    
    -- 2. 解析 Camera 状态
    local cam_hmirror = (cam_mode & 2) == 2
    local cam_vflip   = (cam_mode & 1) == 1

    print("\n============================================")
    print(">> [当前档位]: ", mode, " / 31")
    print(">> LCD 设置 -> 切轴:", lcd_swap, " 镜像X:", lcd_mir_x, " 镜像Y:", lcd_mir_y)
    print(">> CAM 设置 -> 镜像H:", cam_hmirror, " 翻转V:", cam_vflip)
    print("============================================")

    LCD_Set_Dir(lcd_swap, lcd_mir_x, lcd_mir_y)
    Camera_Set_Dir(cam_hmirror, cam_vflip)
end

Apply_Calibration()

while true do
    local pressed, x, y = Touch_Get()
    
    if pressed and not last_touched then
        mode = (mode + 1) % 32
        Apply_Calibration()
        C_OS.vTaskDelay(50) -- 防抖
    end
    last_touched = pressed

    local fb_ptr, len = Camera_Capture()
    if L2C_PtrAsInt(fb_ptr) ~= 0 then
        LCD_Draw_Cam_Frame(fb_ptr)
        Camera_Release(fb_ptr)
    end
    
    C_OS.vTaskDelay(1)
end