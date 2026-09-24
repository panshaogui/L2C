-- 独立视觉与神经沙盒
-- @l2c_import: std/camera.tl
-- @l2c_import: std/touch.tl
-- @l2c_import: std/lcd.tl

print("\n============================================")
print("  L2C 视觉中枢与神经感知 独立系统启动！")
print("============================================\n")

if not Touch_Init() then
    print(" [ERROR] 触摸屏 (CST816) I2C 唤醒失败！")
else
    print(" [OK] 触觉神经上线。")
end

if not Camera_Init() then
    print(" [ERROR] 全知之眼 (OV2640) DMA 初始化失败！可能缺 PSRAM。")
else
    print(" [OK] 全知之眼挂载完毕，PSRAM 缓冲已接管。")
end

-- 【核心修复：在进入高频流水线前，点亮 LCD 视网膜！】
if not LCD_Init() then
    print(" [ERROR] LCD 屏幕 SPI 引擎启动失败！")
else
    print(" [OK] 视网膜点亮！开始硬件级画面直通...")
end

local type C_OS = record
    vTaskDelay: function(integer)
end

local frame_count = 0

-- 绝杀死循环：同时处理画面与触摸，CPU 保持绝对冰凉！
while true do
    -- 1. 神经感知：微秒级读取触摸坐标
    local pressed, x, y = Touch_Get()
    if pressed then
        print(" [击中] 屏幕发生物理触控！X: ", x, " Y: ", y)
    end
    
    -- 2. 视觉截获：0-GC 获取物理显存指针
    local fb_ptr, len = Camera_Capture()
    if L2C_PtrAsInt(fb_ptr) ~= 0 then
        frame_count = frame_count + 1
        
        -- 核心：必须提取真实的像素指针 (pixels)，绝对不能把结构体 (fb_ptr) 扔给屏幕！
        -- local pixels = Camera_Get_Pixels(fb_ptr)
        -- 呼叫顺时针 90度 桥梁
        -- C_LCD.l2c_lcd_draw_cam_cw90(pixels)
        LCD_Draw_Cam_Frame(fb_ptr)

        if frame_count % 30 == 0 then
            print(" [视觉] 成功将第 ", frame_count, " 帧砸向屏幕！")
        end
        
        -- 用完必须立刻交还给 DMA！
        Camera_Release(fb_ptr)
    end
    
    -- 极其关键的降温神技！每次循环让出 20ms 给 FreeRTOS，极限省电！
    C_OS.vTaskDelay(2) 
end