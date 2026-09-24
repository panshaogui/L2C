-- @l2c_import: std/sdcard.tl
-- @l2c_import: std/camera.tl

local type C_OS = record
    vTaskDelay: function(integer)
end

print("\n============================================")
print("  [砖块 7] 全知之眼法医取证系统 (JPEG + SD)")
print("============================================\n")

-- 微雪真实图纸坐标：MISO=40, MOSI=38, SCK=39, CS=41
-- [修复] Lua 的 0 是 True，必须严谨判断 == 1
if SDCard_init1(40, 38, 39, 41) then
    print(" [OK] TF 卡 (共享 SPI) 挂载成功！")
else
    print(" [ERROR] TF 卡挂载失败！请检查 TF 卡是否插入或引脚是否正确。")
    return
end

-- 2. 以 JPEG 模式点亮视网膜
if not Camera_Init_JPEG() then
    print(" [ERROR] 摄像头 JPEG 模式启动失败！")
    return
else
    print(" [OK] 摄像头已进入高分辨率 (VGA) JPEG 模式！")
end

-- 给摄像头 1 秒的时间自动曝光和白平衡稳定
print(">> 等待 1 秒进行白平衡与自动对焦...")
C_OS.vTaskDelay(100)

-- 3. 咔嚓！按下快门
print(">>  正在抓拍画面并写入 TF 卡物理扇区...")

-- 假设底层 mount 挂载的绝对路径前缀是 "/sdcard"
local res = Camera_Save_JPG("/sd/test002.jpg") 

if res == 1 then
    print("\n [取证成功] 图片已完美保存在 TF 卡 /sdcard/test001.jpg 中！")
    print(" [下一步行动] 请拔下 TF 卡，插入 Mac 电脑查看画面是否清晰和方向是否正确！")
elseif res == -1 then
    print("\n [文件系统错误] 抓拍到了内存，但无法创建文件！请检查 /sdcard 路径是否正确。")
else
    print("\n [硬件错误] 无法从摄像头获取 JPEG 帧！")
end