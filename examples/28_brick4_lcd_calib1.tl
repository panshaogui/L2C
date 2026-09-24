-- @l2c_import: std/lcd.tl

local type C_OS = record
    vTaskDelay: function(integer)
end

print("\n============================================")
print("  [砖块 4] 竖屏 (240x320) LCD 物理定标测试")
print("============================================\n")

if not LCD_Init() then
    print(" [ERROR] LCD 初始化失败！")
    return
end

print(">> 1. 纯色定标：红色 (Red) ...")
LCD_Fill(255, 0, 0)
C_OS.vTaskDelay(100)

print(">> 2. 纯色定标：绿色 (Green) ...")
LCD_Fill(0, 255, 0)
C_OS.vTaskDelay(100)

print(">> 3. 纯色定标：蓝色 (Blue) ...")
LCD_Fill(0, 0, 255)
C_OS.vTaskDelay(100)

LCD_Fill(0, 0, 0)

-- 左上角锚点 (0, 0)
LCD_Draw_Rect(0, 0, 50, 50, 255, 255, 255)
print(">> 【左上角】应该出现：白色正方形 (0,0)")

-- 右下角锚点 (240-50, 320-50)
LCD_Draw_Rect(190, 270, 50, 50, 255, 0, 0)
print(">> 【右下角】应该出现：红色正方形 (240,320)")

print("\n [定标指南] 如果红/白锚点位置不对，请在 C 层调整 swap_xy 和 mirror！")