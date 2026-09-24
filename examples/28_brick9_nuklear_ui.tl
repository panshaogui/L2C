-- @l2c_import: std/lcd.tl
-- @l2c_import: std/touch.tl
-- @l2c_import: std/nuklear.tl
-- @l2c_import: std/stackstring.tl

local type C_OS = record vTaskDelay: function(integer) end

print("\n============================================")
print("  [砖块 9] Nuklear 0-GC 战术仪表盘点火")
print("============================================\n")

if not LCD_Init() then print("LCD 失败") return end
if not Touch_Init() then print("Touch 失败") return end
if not NK_Init() then print("Nuklear 内存分配失败") return end

print(">> [OK] 视觉、神经与 GUI 核心交织完毕！进入主循环！")

local counter = 0

while true do
    -- 1. 神经感知：把触摸坐标喂给 Nuklear
    local pressed, x, y = Touch_Get()
    NK_Input(pressed, x, y)

    -- 2. 战术界面绘制 (Immediate Mode：代码即界面！)
    if NK_Begin("L2C Command Center", 10, 10, 220, 200) then
        
        -- 画一行：占 30 像素高，平分 1 列
        NK_Layout_Row(30, 1)
        NK_Label("Status: SCANNING...")
        
        -- 画一行：平分 2 列
        NK_Layout_Row(40, 2)
        if NK_Button("TX Hello") then
            print(" 触发：发送 Hello 广播！")
            counter = counter + 1
        end
        if NK_Button("TX POS") then
            print(" 触发：发送假 GPS 坐标！")
            counter = counter + 1
        end

        -- 画一行：展示计数器
        NK_Layout_Row(30, 1)
        local buf = L2C_Buffer(32)
        local str = L2C_Ref(buf)
        StackStr_init(str)
        StackStr_append_str(str, 32, "Fired Shots: ")
        StackStr_append_int(str, 32, counter)
        NK_Label(StackStr_get(str))

    end
    NK_End()

    -- 3. 极速降维，打入屏幕！
    NK_Render()
    
    -- 锁频防烫：给出 10ms 的 CPU 喘息时间，维持 100FPS 的惊人刷新率！
    C_OS.vTaskDelay(1) 
end