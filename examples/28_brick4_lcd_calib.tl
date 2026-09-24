-- @l2c_import: std/lcd.tl

local type C_OS = record
    vTaskDelay: function(integer)
end

print("\n============================================")
print("  [砖块 4] 横屏 (320x240) LCD 屏幕物理定标测试")
print("============================================\n")

if not LCD_Init() then
    print(" [ERROR] LCD 初始化失败！")
    return
end

print(">> 1. 正在测试纯色：红 (Red) ...")
LCD_Fill(255, 0, 0)
C_OS.vTaskDelay(100) -- 延时 1 秒 (100 * 10ms)

print(">> 2. 正在测试纯色：绿 (Green) ...")
LCD_Fill(0, 255, 0)
C_OS.vTaskDelay(100)

print(">> 3. 正在测试纯色：蓝 (Blue) ...")
LCD_Fill(0, 0, 255)
C_OS.vTaskDelay(100)

print(">> 4. 清屏为黑色，并进行坐标系测试 ...")
LCD_Fill(0, 0, 0)

-- 在左上角 (0, 0) 画一个 50x50 的白色正方形
LCD_Draw_Rect(0, 0, 50, 50, 255, 255, 255)
print(">> 白色的方块应该出现在物理屏幕的【左上角 (0,0)】！")

-- 在右下角画一个红色的长方形
LCD_Draw_Rect(270, 190, 50, 50, 255, 0, 0)
print(">> 红色的方块应该出现在物理屏幕的【右下角 (320,240)】！")

print("\n [定标结束] 如果颜色不对，请修改 C 底层的 LCD_RGB_ENDIAN！")
print("            如果方位不对，请修改 C 底层的 swap_xy 或 mirror！")