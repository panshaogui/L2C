-- @l2c_import: std/lcd.tl
-- @l2c_import: std/touch.tl

local type C_OS = record
    vTaskDelay: function(integer)
end

print("\n============================================")
print("  [砖块 5] 竖屏 (240x320) 触觉神经同步标定")
print("============================================\n")

LCD_Init()
Touch_Init()
LCD_Fill(0, 0, 0)

-- 左上角 (X:0~50, Y:0~50)
LCD_Draw_Rect(0, 0, 50, 50, 255, 0, 0)
print(">> 红块 -> X 接近 0, Y 接近 0")

-- 右上角 (X:190~240, Y:0~50)
LCD_Draw_Rect(190, 0, 50, 50, 0, 255, 0)
print(">> 绿块 -> X 接近 240, Y 接近 0")

-- 左下角 (X:0~50, Y:270~320)
LCD_Draw_Rect(0, 270, 50, 50, 0, 0, 255)
print(">> 蓝块 -> X 接近 0, Y 接近 320")

-- 右下角 (X:190~240, Y:270~320)
LCD_Draw_Rect(190, 270, 50, 50, 255, 255, 255)
print(">> 白块 -> X 接近 240, Y 接近 320")

while true do
    local pressed, x, y = Touch_Get()
    if pressed then
        print(" 触控坐标 -> X: ", x, " | Y: ", y)
        C_OS.vTaskDelay(20) -- 防抖
    end
    C_OS.vTaskDelay(2) 
end