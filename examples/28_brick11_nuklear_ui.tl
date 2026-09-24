-- @l2c_import: std/lcd.tl
-- @l2c_import: std/touch.tl
-- @l2c_import: std/camera.tl
-- @l2c_import: std/nuklear.tl
-- @l2c_import: std/stackstring.tl

local type C_OS = record
    vTaskDelay: function(integer)
end

print("\n============================================")
print("  [L2C 旗舰] 双栖形态战术控制中心启动")
print("============================================\n")

LCD_Init()
Touch_Init()

-- [核心状态机] true = 分屏阿帕奇模式；false = 全屏雷达模式
local is_camera_mode = false
local has_cam = false

-- 1. 无参初始化，开辟最大物理水库！
if not NK_Init() then
    print(" [ERROR] Nuklear 显存水库开辟失败！")
    return
end

-- 2. 默认进入：全屏雷达模式 (240x320)
NK_Resize(240, 320)

local shot_count = 0

while true do
    local pressed, x, y = Touch_Get()

    if is_camera_mode then
        -- ==========================================================
        -- 【形态 A】分屏阿帕奇座舱 (上 240 摄像头，下 80 战术面板)
        -- ==========================================================
        NK_Input(pressed, x, y, 240) -- 阻断 240 以上的触摸

        if NK_Begin("Optics HUD", 0, 0, 240, 80) then
            NK_Layout_Row(25, 2)
            
            -- [返回按钮] 点击后瞬间切回全屏雷达！
            if NK_Button("<< Close") then
                is_camera_mode = false
                NK_Resize(240, 320) -- 动态重置画板大小！
                print(">> [形态切换] 回退至全屏雷达模式")
            end
            
            if NK_Button("TX Fire") then
                shot_count = shot_count + 1
                print(" 发射！当前弹药消耗: ", shot_count)
            end
        end
        NK_End()

        -- 渲染上半屏摄像头
        if has_cam then
            local fb_ptr = Camera_Capture()
            if L2C_PtrAsInt(fb_ptr) ~= 0 then
                LCD_Draw_Cam_Frame(fb_ptr)
                Camera_Release(fb_ptr)
            end
        end

        -- 渲染下半屏 UI (Y偏移 240，宽高 240x80)
        NK_Render(240, 240, 80)

    else
        -- ==========================================================
        -- 【形态 B】全屏雷达指挥台 (满血 240x320 UI 面板)
        -- ==========================================================
        NK_Input(pressed, x, y, 0) -- 全屏触控，0 偏移

        if NK_Begin("L2C Radar Console", 0, 0, 240, 320) then
            
            NK_Layout_Row(40, 1)
            -- [开启按钮] 点击后瞬间切入分屏光学瞄准！
            if NK_Button(">> ENABLE OPTICS") then
                -- 延迟加载摄像头，省电又安全！
                if not has_cam then
                    print(">> 正在预热全知之眼...")
                    has_cam = Camera_Init()
                end
                
                if has_cam then
                    is_camera_mode = true
                    NK_Resize(240, 80) -- 动态压缩画板大小！
                    print(">> [形态切换] 切入阿帕奇分屏座舱")
                else
                    print(" [ERROR] 摄像头预热失败！无法开启光学瞄准。")
                end
            end

            NK_Layout_Row(30, 2)
            if NK_Button("FREQ 470") then print(" 调频 470.030 MHz") end
            if NK_Button("FREQ 433") then print(" 调频 433.875 MHz") end

            NK_Layout_Row(30, 1)
            if NK_Button("Start SCAN Sweep") then print(" 雷达开始扫频...") end

            -- 留出大块空白区域给未来的截获情报日志
            NK_Layout_Row(100, 1)
            NK_Label("Awaiting Interception...")
        end
        NK_End()

        -- 渲染全屏 UI (Y偏移 0，宽高 240x320)
        NK_Render(0, 240, 320)
    end

    C_OS.vTaskDelay(2) 
end