-- @l2c_import: std/lcd.tl
-- @l2c_import: std/touch.tl
-- @l2c_import: std/camera.tl
-- @l2c_import: std/nuklear.tl
-- @l2c_import: std/stackstring.tl

local type C_OS = record
    vTaskDelay: function(integer)
end

print("\n============================================")
print("  [L2C 旗舰] 阿帕奇空地一体化分屏座舱 (HUD)")
print("============================================\n")

LCD_Init()
Touch_Init()

-- ==========================================================
-- 战术面板尺寸定义 (下半截屏幕)
-- ==========================================================
local UI_W = 240        -- UI 宽度 240 (撑满横向)
local UI_H = 80         -- UI 高度 80 (占底部 1/4)
local UI_OFFSET_Y = 240 -- UI 起始 Y 坐标 (垫在摄像头下面)

-- [回归真理] 1. 无参初始化，开辟最大物理水库！
if not NK_Init() then
    print(" [ERROR] Nuklear 显存水库开辟失败！")
    return
else
    print(" [OK] 战术控制台 0-GC 显存已分配 (最大容量 240x320)")
end

-- [回归真理] 2. 动态切割视口，把 Nuklear 限制在 240x80 内！
NK_Resize(UI_W, UI_H)

local has_cam = Camera_Init()
if has_cam then
    print(" [OK] 全知之眼已挂载，准备投射上半屏 (240x240)！")
end

local shot_count = 0

-- 绝杀主循环
while true do
    -- 1. 神经感知：带有物理阻断的触觉输入
    local pressed, x, y = Touch_Get()
    -- 传入 UI_OFFSET_Y，阻断上方摄像头区域的误触，并修正 Y 轴坐标！
    NK_Input(pressed, x, y, UI_OFFSET_Y)

    -- 2. 战术面板绘制 (逻辑尺寸从 0,0 开始，宽 240，高 80)
    if NK_Begin("L2C Command", 0, 0, UI_W, UI_H) then
        
        NK_Layout_Row(25, 2)
        if NK_Button("TX Fire") then
            shot_count = shot_count + 1
            print(" 发射！当前弹药消耗: ", shot_count)
        end
        if NK_Button("SCAN") then
            print(" 启动全频段雷达扫描！")
        end

        NK_Layout_Row(25, 1)
        local buf = L2C_Buffer(64)
        local str = L2C_Ref(buf)
        StackStr_init(str)
        StackStr_append_str(str, 64, "Status: ARMED | Shots: ")
        StackStr_append_int(str, 64, shot_count)
        NK_Label(StackStr_get(str))
        
    end
    NK_End()

    -- 3. 物理层送显 A：上半屏 (0~239) 渲染实时摄像头画面
    if has_cam then
        local fb_ptr = Camera_Capture()
        if L2C_PtrAsInt(fb_ptr) ~= 0 then
            LCD_Draw_Cam_Frame(fb_ptr) -- 底层自动裁切为 240x240 并定格在上半部
            Camera_Release(fb_ptr)
        end
    end

    -- 4. 物理层送显 B：下半屏 (240~319) 渲染 Nuklear 战术面板
    -- 告诉底层：贴纸大小是 w, h，请贴在 offset_y 的位置！
    NK_Render(UI_OFFSET_Y, UI_W, UI_H)

    -- 防过热锁帧
    C_OS.vTaskDelay(2) 
end