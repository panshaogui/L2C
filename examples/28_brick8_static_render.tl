-- @l2c_import: std/sdcard.tl
-- @l2c_import: std/lcd.tl

print("\n============================================")
print("  [砖块 8] 静态 JPEG 绝对视网膜定标")
print("============================================\n")

-- 1. 挂载黑匣子 (微雪图纸绝对坐标)
if SDCard_init1(40, 38, 39, 41) then
    print(" [OK] TF 卡 (共享 SPI) 挂载成功！")
else
    print(" [ERROR] TF 卡挂载失败！请检查引脚或卡槽。")
    return
end

-- 2. 点亮视网膜
if not LCD_Init() then
    print(" [ERROR] LCD 屏幕初始化失败！")
    return
else
    print(" [OK] 视网膜点亮，准备接收图像...")
end

-- 3. 读取并解码照片
print(">> 正在从 TF 卡加载 test001.jpg，执行硬件降维解码 (640x480 -> 320x240)...")
local res = LCD_Draw_JPG_From_SD("/sd/test002.jpg")

if res == 1 then
    print(" [成功] 图像已完美渲染至屏幕！请用您的肉眼进行法医鉴定！")
elseif res == -1 then
    print(" [失败] 找不到文件 /sd/test001.jpg")
elseif res == -4 then
    print(" [失败] JPEG 格式损坏，硬件解码失败！")
else
    print(" [失败] 内存不足或底层异常，错误码: ", res)
end