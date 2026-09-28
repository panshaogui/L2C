-- @l2c_import: std/esp32.tl
-- @l2c_import: std/lcd.tl
-- @l2c_import: std/touch.tl
-- @l2c_import: std/camera.tl
-- @l2c_import: std/nuklear.tl
-- @l2c_import: std/nvs.tl
-- @l2c_import: std/sdcard.tl
-- @l2c_import: std/ble_nus.tl
-- @l2c_import: std/uart.tl 
-- @l2c_import: std/wifi.tl
-- @l2c_import: std/ntp.tl
-- @l2c_import: std/udp.tl
-- @l2c_import: std/ota.tl
-- @l2c_import: std/stackstring.tl
-- @l2c_import: std/multicore.tl
-- @l2c_import: std/c2_engine.tl

local type C_OS = record vTaskDelay: function(integer) end

print("\n============================================")
print("  [L2C 旗舰] 移动战术指挥看板 (C2 Dashboard) 上线")
print("============================================\n")

-- ==========================================================
-- 1. 物理层挂载 (存储、视觉、触觉)
-- ==========================================================
NVS_init()

SPI_Bus_Init(1, 40, 38, 39)

if SDCard_init1(40, 38, 39, 41) then
    print(" [OK] 战术黑匣子 (SDMMC) 挂载成功！")
end

LCD_Init()
Touch_Init()
NK_Init() -- 默认全屏模式

-- 绝对不能在点击按钮时才初始化！必须趁 WiFi 和 BLE 还没启动、内存最纯净时，
-- 强行划走那 30KB 连续内部 SRAM，用于铺设 DMA 乒乓缓冲！
print(" [INIT] 正在预热全知之眼...")
local has_cam = Camera_Init()
local is_camera_mode = false

-- ==========================================================
-- 2. 蓝牙近场接管 (用于配置 WiFi 和 OTA)
-- ==========================================================
BLE_init()
print(" [BLE] 蓝牙配置通道已开启，设备名: L2C-Mesh")

-- ==========================================================
-- 3. 自治网络引擎 (NVS 加密提取)
-- ==========================================================
local w_ssid_buf = L2C_Buffer(64); local w_ssid_str = L2C_Ref(w_ssid_buf); StackStr_init(w_ssid_str)
local w_pwd_buf  = L2C_Buffer(64); local w_pwd_str  = L2C_Ref(w_pwd_buf);  StackStr_init(w_pwd_str)
local was_connected = false
local ip_buf = L2C_Buffer(32); local ip_str = L2C_Ref(ip_buf); StackStr_init(ip_str)

if C_NVS.l2c_nvs_get_stackstr("w_ssid", w_ssid_str, 64) == 1 and 
   C_NVS.l2c_nvs_get_stackstr("w_pwd", w_pwd_str, 64) == 1 then
    
    -- 将 NVS 里取出的扩展 ASCII 乱码进行 XOR 对称还原！
    NVS_Cipher_StackStr(w_ssid_str)
    NVS_Cipher_StackStr(w_pwd_str)
    
    local ssid_plain = StackStr_get(w_ssid_str)
    local pwd_plain = StackStr_get(w_pwd_str)
    
    print(" [WiFi] 密文凭证提取并解密成功！启动网卡连接: ", ssid_plain)
    
    -- 呼叫您底层的 WiFi 初始化探针 (请确保函数名与 std/wifi.tl 对齐)
    WIFI_init_sta(ssid_plain, pwd_plain) 
else
    print(" [WiFi] NVS 黑匣子内无凭据。Wi-Fi 引擎已挂起，等待蓝牙指令注入。")
end

-- 为 UART 和 BLE 各准备一个解析缓冲，物理隔离防止乱码串台！

local ble_rx_buf = L2C_Buffer(128); 
local ble_str = L2C_Ref(ble_rx_buf); 
StackStr_init(ble_str)

local uart_rx_buf = L2C_Buffer(128); 
local uart_str = L2C_Ref(uart_rx_buf);
StackStr_init(uart_str)

-- ==========================================================
-- [战术解耦] 本地配置指令处理器 (WIFI / OTA 共享解析)
-- ==========================================================
local function Process_Local_Config_Cmd(cmd_str: any)
    if StackStr_startswith(cmd_str, "WIFI ") then
        local cmd_len = StackStr_len(cmd_str)
        local space_idx = -1
        
        -- 极速探针：寻找热点名和密码之间的空格
        for i = 5, cmd_len - 1 do
            if C_ESP_IDF.l2c_get_byte(cmd_str, 1 + i) == 32 then
                space_idx = i
                break
            end
        end
        
        if space_idx > 0 then
            local ssid_buf = L2C_Buffer(64); local ssid_str = L2C_Ref(ssid_buf); StackStr_init(ssid_str)
            local pwd_buf  = L2C_Buffer(64); local pwd_str  = L2C_Ref(pwd_buf);  StackStr_init(pwd_str)
            
            -- 0-GC 游标提取 SSID 和 PASSWORD
            for i = 5, space_idx - 1 do StackStr_append_char(ssid_str, 64, C_ESP_IDF.l2c_get_byte(cmd_str, 1 + i)) end
            for i = space_idx + 1, cmd_len - 1 do StackStr_append_char(pwd_str, 64, C_ESP_IDF.l2c_get_byte(cmd_str, 1 + i)) end
            
            print(">> [WIFI] 收到新热点配置: ", StackStr_get(ssid_str))
            
            -- 物理扰乱！
            NVS_Cipher_StackStr(ssid_str)
            NVS_Cipher_StackStr(pwd_str)
            
            -- 砸入底层 NVS (需要 C_ESP_IDF 里有这俩探针的声明)
            C_NVS.l2c_nvs_set_stackstr("w_ssid", ssid_str)
            C_NVS.l2c_nvs_set_stackstr("w_pwd", pwd_str)
            
            print(">> [WIFI] 凭据已加密打入 NVS 黑匣子！下次重启生效。")
        else
            print(">> [错误] 格式不对！请使用: WIFI <SSID> <PASSWORD>")
        end
    elseif StackStr_startswith(cmd_str, "OTA ") then
        -- 解析出 http://... 的 URL
        local url_buf = L2C_Buffer(128); 
        local url_str = L2C_Ref(url_buf);
        StackStr_init(url_str)
        local cmd_len = StackStr_len(cmd_str)
        for i = 4, cmd_len - 1 do
            StackStr_append_char(url_str, 128, C_ESP_IDF.l2c_get_byte(cmd_str, 1 + i))
        end
        print(">> [COMMAND] 收到最高空中指令，准备拉取固件: ", StackStr_get(url_str))
        -- 呼叫 OTA 线程
        OTA_Start(StackStr_get(url_str))
    end
end

-- ==========================================================
-- 4. 通讯兵：Core 1 异步网络与情报监听引擎
-- ==========================================================
local function Core1_CommsTask()
    print(" [Core 1] 战术通讯兵已上线，接管无线电与串口矩阵！")
    UART_init()
    
    local udp_rx_buf = L2C_Buffer(128); 
    local udp_str = L2C_Ref(udp_rx_buf)

    local ip_buf = L2C_Buffer(4); 
    local ip_ptr = L2C_Ref(ip_buf)

    local was_conn = false

    while true do
        local is_conn = WIFI_is_connected()
        
        -- WiFi 状态机
        if is_conn and not was_conn then
            was_conn = true
            WIFI_Disable_PowerSave() -- 拒绝休眠，1ms 级极速响应！
            UDP_server_init(8888)    -- 监听僚机战报
            NTP_init()               -- 同步绝对时间
            print(" [Core 1] 战术雷达 8888 端口与 NTP 时间引擎已点火！")
        elseif not is_conn and was_conn then
            was_conn = false
        end

        -- 极速 UDP 弹仓检查：提取情报并获取来源 IP！
        if is_conn and UDP_pop_cmd_with_ip(udp_str, 128, ip_ptr) then
            -- 提取 32 位整型 IP 坐标
            local b0 = C_ESP_IDF.l2c_get_byte(ip_ptr, 0)
            local b1 = C_ESP_IDF.l2c_get_byte(ip_ptr, 1)
            local b2 = C_ESP_IDF.l2c_get_byte(ip_ptr, 2)
            local b3 = C_ESP_IDF.l2c_get_byte(ip_ptr, 3)
            local sender_ip = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
            
            -- [核心] 将来源节点编入现役阵列，刷新寿命！
            local is_new = C2_Fleet_Update(sender_ip)
            if is_new then
                print(" [Core 1] 新节点入列！IP INT: ", sender_ip)
            end

            -- [0-GC 隔离通道] 将字符串战报压入无锁队列，交由 Core 0 处理！
            C2_Msg_Push(udp_str)
        end

        -- 【链路 2：处理本地蓝牙配网指令】
        local bc = BLE_pop_char()
        while bc > 0 do
            if bc == 10 or bc == 13 then
                if StackStr_len(ble_str) > 0 then
                    print(" [蓝牙] 收到配置: ", StackStr_get(ble_str))
                    Process_Local_Config_Cmd(ble_str)
                    StackStr_clear(ble_str)
                end
            else
                StackStr_append_char(ble_str, 128, bc)
            end
            bc = BLE_pop_char()
        end

        -- 【链路 3：原生串口键盘配置】
        local uc = UART_read_char()
        while uc > 0 do
            if uc == 10 or uc == 13 then
                if StackStr_len(uart_str) > 0 then
                    print(" [串口] 收到配置: ", StackStr_get(uart_str))
                    Process_Local_Config_Cmd(uart_str)
                    StackStr_clear(uart_str)
                end
            else
                if uc >= 32 and uc <= 126 then -- 只存可见字符
                    StackStr_append_char(uart_str, 128, uc)
                end
            end
            uc = UART_read_char()
        end

        -- 微秒级让出时间片，绝对不导致看门狗报警
        C_OS.vTaskDelay(1)
    end
end

-- 启动 Core 1
Multicore_Launch(Core1_CommsTask)

-- ==========================================================
-- 5. 指挥官：Core 0 滚动日志池与舰队广播引擎
-- ==========================================================
-- 0-GC 滚动日志区 (严禁使用 Table，展开为独立栈指针！)
local log1_buf = L2C_Buffer(128); local log1 = L2C_Ref(log1_buf); StackStr_init(log1)
local log2_buf = L2C_Buffer(128); local log2 = L2C_Ref(log2_buf); StackStr_init(log2)
local log3_buf = L2C_Buffer(128); local log3 = L2C_Ref(log3_buf); StackStr_init(log3)
local log4_buf = L2C_Buffer(128); local log4 = L2C_Ref(log4_buf); StackStr_init(log4)

StackStr_append_str(log1, 128, "Awaiting Intel...") -- 初始占位符

local pop_str = L2C_Ref(L2C_Buffer(128))

-- [战术动作] 向编队内的所有存活节点发射 UDP 广播！
local function Fleet_Broadcast(cmd: string, len: integer)
    local ip_arr_buf = L2C_Buffer(32) -- 足够容纳 8 个 32位 IP
    local ip_arr = L2C_Ref(ip_arr_buf)
    local active_cnt = C2_Fleet_Get_Active(ip_arr)
    
    local ip_str_buf = L2C_Buffer(32)
    local ip_str = L2C_Ref(ip_str_buf)

    for i = 0, active_cnt - 1 do
        local b0 = C_ESP_IDF.l2c_get_byte(ip_arr, i * 4)
        local b1 = C_ESP_IDF.l2c_get_byte(ip_arr, i * 4 + 1)
        local b2 = C_ESP_IDF.l2c_get_byte(ip_arr, i * 4 + 2)
        local b3 = C_ESP_IDF.l2c_get_byte(ip_arr, i * 4 + 3)
        local target_ip = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
        
        IP_to_Str(target_ip, ip_str)
        UDP_send(StackStr_get(ip_str), 8889, cmd, len)
    end
end

-- ==========================================================
-- 6. 终极机甲主循环 (UI 渲染 + 触控 + 摄像头 DMA)
-- ==========================================================
local shot_count = 0

while true do
    -- 1. 处理 Core 1 传过来的战报 (提取并写入物理 SD 卡)
    if C2_Msg_Pop(pop_str) then
        -- [硬核指针平移] 滚动记录，不用 Table，直接倒推！
        StackStr_copy(log4, log3, 128)
        StackStr_copy(log3, log2, 128)
        StackStr_copy(log2, log1, 128)
        StackStr_copy(log1, pop_str, 128)

        -- 极其安全的同线程 SD 卡写入，绝不和 LCD 的 SPI 冲突！
        SDCard_append("c2_radar.log", StackStr_get(pop_str))
    end

    -- 2. 读取触摸坐标与视口防抖
    local pressed, x, y = Touch_Get()
    local ui_offset = is_camera_mode and 240 or 0
    local ui_h = is_camera_mode and 80 or 320
    NK_Input(pressed, x, y, ui_offset)

    -- 3. 绘制 Nuklear 战术面板
    if NK_Begin("C2 Command", 0, 0, 240, ui_h) then
        
        if is_camera_mode then
            -- 【形态 A：阿帕奇分屏座舱】
            NK_Layout_Row(25, 2)
            if NK_Button("<< MAP") then
                is_camera_mode = false
                NK_Resize(240, 320)
            end
            if NK_Button("FIRE") then
                shot_count = shot_count + 1
                Fleet_Broadcast("TX FIRE", 7)
            end
            NK_Layout_Row(20, 1)
            NK_Label("Status: OPTICS ENGAGED")
        else
            -- 【形态 B：全屏雷达大盘】
            NK_Layout_Row(30, 1)
            if NK_Button(">> ENABLE OPTICS") then
                if has_cam then
                    is_camera_mode = true
                    NK_Resize(240, 80)
                end
            end
            
            NK_Layout_Row(30, 2)
            if NK_Button("SCAN") then Fleet_Broadcast("SCAN", 4) end
            if NK_Button("FREQ 470") then Fleet_Broadcast("FREQ 470030", 11) end
            
            NK_Layout_Row(20, 1)
            NK_Label("---- FLEET STATUS ----")
            
            local ip_arr_buf = L2C_Buffer(32)
            local fleet_cnt = C2_Fleet_Get_Active(L2C_Ref(ip_arr_buf))
            local ip_str = L2C_Ref(L2C_Buffer(32))
            
            if fleet_cnt == 0 then
                NK_Label("No active nodes.")
            else
                for i = 0, fleet_cnt - 1 do
                    local b0 = C_ESP_IDF.l2c_get_byte(L2C_Ref(ip_arr_buf), i * 4)
                    local b1 = C_ESP_IDF.l2c_get_byte(L2C_Ref(ip_arr_buf), i * 4 + 1)
                    local b2 = C_ESP_IDF.l2c_get_byte(L2C_Ref(ip_arr_buf), i * 4 + 2)
                    local b3 = C_ESP_IDF.l2c_get_byte(L2C_Ref(ip_arr_buf), i * 4 + 3)
                    IP_to_Str(b0 | (b1 << 8) | (b2 << 16) | (b3 << 24), ip_str)
                    
                    local active_txt = L2C_Ref(L2C_Buffer(64)); StackStr_init(active_txt)
                    StackStr_append_str(active_txt, 64, "[ON] ")
                    StackStr_append_str(active_txt, 64, StackStr_get(ip_str))
                    NK_Label(StackStr_get(active_txt))
                end
            end

            NK_Layout_Row(20, 1)
            NK_Label("---- INTEL FEED ----")
            NK_Label(StackStr_get(log1))
            NK_Label(StackStr_get(log2))
            NK_Label(StackStr_get(log3))
            NK_Label(StackStr_get(log4))
        end
    end
    NK_End()

    -- 7. 物理层送显：上摄像头，下 UI
    if is_camera_mode and has_cam then
        local fb_ptr = Camera_Capture()
        if L2C_PtrAsInt(fb_ptr) ~= 0 then
            LCD_Draw_Cam_Frame(fb_ptr)
            Camera_Release(fb_ptr)
        end
    end

    NK_Render(ui_offset, 240, ui_h)

    C_OS.vTaskDelay(2) 
end