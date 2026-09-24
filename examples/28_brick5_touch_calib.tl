-- @l2c_import: std/lcd.tl
-- @l2c_import: std/touch.tl

local type C_OS = record
    vTaskDelay: function(integer)
end

print("\n============================================")
print("  [砖块 5] 横屏 (320x240) 视触觉神经同步定标测试")
print("============================================\n")

LCD_Init()
Touch_Init()

LCD_Fill(0, 0, 0) -- 黑底

-- 左上角画红色块 (X:0~50, Y:0~50)
LCD_Draw_Rect(0, 0, 50, 50, 255, 0, 0)
-- 右上角画绿色块 (X:270~320, Y:0~50)
LCD_Draw_Rect(270, 0, 50, 50, 0, 255, 0)
-- 左下角画蓝色块 (X:0~50, Y:190~240)
LCD_Draw_Rect(0, 190, 50, 50, 0, 0, 255)
-- 右下角画白色块 (X:270~320, Y:190~240)
LCD_Draw_Rect(270, 190, 50, 50, 255, 255, 255)

print(">> 标定画面已加载！")
print(">> 请依次用手指戳击：红 -> 绿 -> 蓝 -> 白")

while true do
    local pressed, x, y = Touch_Get()
    if pressed then
        print(" [触控命中] 当前解析坐标 -> X: ", x, " | Y: ", y)
        C_OS.vTaskDelay(20) -- 防抖延时 200ms，防止疯狂刷屏
    end
    C_OS.vTaskDelay(2) 
end