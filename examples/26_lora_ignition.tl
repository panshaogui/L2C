-- examples/26_lora_ignition.tl

--@l2c_import: std/esp32.tl
--@l2c_import: std/oled_ssd1306.tl
--@l2c_import: std/nvs.tl
--@l2c_import: std/sdcard.tl
--@l2c_import: std/lora_sx1262.tl
--@l2c_import: std/uart.tl
--@l2c_import: std/ble_nus.tl
--@l2c_import: std/stackstring.tl
--@l2c_import: std/cmd_queue.tl
--@l2c_import: std/wifi.tl
--@l2c_import: std/ntp.tl
--@l2c_import: std/udp.tl

-- EoRa-S3 默认 OLED 引脚: SDA=18, SCL=17

OLED_init(18, 17)
OLED_clear() 

NVS_init()

OLED_print(0, "L2C-Mesh Node v1.0")
OLED_print(1, "===================")
OLED_print(2, "Initializing RF...")

-- 点亮战术黑匣子
if SDCard_init(EORA_BOARD.SD_MISO, EORA_BOARD.SD_MOSI, EORA_BOARD.SD_SCK, EORA_BOARD.SD_CS) then
    OLED_print(5, "SD Card: [MOUNTED]")
    print(" [SDCard] 挂载成功！准备写入日志...")
    SDCard_append("radar.log", "=== L2C Node Booted ===")
else
    OLED_print(5, "SD Card: [FAILED]")
    print(" [SDCard] 未检测到 TF 卡，日志功能降级关闭。")
end

SX1262_init()
SX1262_setup_meshtastic_sniffer()
SX1262_setup_rx()

print(" [L2C] 正在挂载 DIO1 硬件上升沿中断...")
C_ESP_IDF.l2c_setup_dio1_interrupt(EORA_BOARD.DIO1)

-- 点亮蓝牙引擎
BLE_init()
print(" [BLE] 蓝牙广播已开启，设备名: L2C-Mesh")
OLED_print(3, "BLE: [BROADCASTING]")

---------------------------------------------------------
-- 副核任务 (Core 1)
---------------------------------------------------------
local function Core1_UartTask()
    UART_init()
    print(" [Core 1] 交互中枢已点火！正在深渊阻塞监听键盘...")
    
    while true do
        local c = UART_read_char()
        if c > 0 then
            -- 【细节修复】：只有可见字符才回显！
            if c >= 32 and c <= 126 then
                print(" [UART]: ", c)
            end
            
            CMD_Push(c)
            -- 跨核闪电突击：踢醒主核！
            C_ESP_IDF.l2c_wake_main_core()
        end
    end
end

-- 点燃第二核心
C_ESP_IDF.l2c_launch_core1(L2C_FuncPtr(Core1_UartTask))

OLED_print(2, "RF Status: [ONLINE]")
OLED_print(7, "FREQ: 470375") -- 默认初始信道

print(" [L2C] 已潜入 CN_470 频段，系统进入静默状态...")

---------------------------------------------------------
-- 0-GC 命令路由中心！
---------------------------------------------------------
local g_is_scanning = false
local g_scan_freq = 470000 -- 从 470.000 MHz 开始扫起！

local function CMD_Process(cmd_str: any)
    local raw_cmd = StackStr_get(cmd_str)
    print(" [L2C-CMD] 开始执行指令: ", raw_cmd)
    
    OLED_clear_3to6()
    OLED_print(3, ">> CMD EXEC")
    OLED_print(4, raw_cmd)

    -- 1. [调频爆破]: FREQ 470375 (单位 kHz)
    if StackStr_startswith(cmd_str, "FREQ ") then
        local khz = StackStr_parse_int(cmd_str, 5)
        local reg = C_ESP_IDF.l2c_sx1262_calc_freq(khz)
        
        -- 位运算拆解为 4 字节
        local b0 = (reg >> 24) & 255
        local b1 = (reg >> 16) & 255
        local b2 = (reg >> 8) & 255
        local b3 = reg & 255
        
        -- 切换到待机模式 (STDBY_RC) 才能配置
        if C_ESP_IDF.l2c_sx1262_wait_busy() then
            C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
            C_ESP_IDF.l2c_sx1262_spi_xfer_2b(0x80, 0x00) 
            C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
        end
        C_ESP_IDF.vTaskDelay(1) 
        
        -- 带有硬件校验的频率重载
        local ok = SX1262_send_cmd5(0x86, b0, b1, b2, b3)
        
        if ok and SX1262_restart_rx_safe(1) then
            print(">> [成功] 中心频率已真实重载为: ", khz, " kHz")
            OLED_print(6, "FREQ Set OK")
            
            -- [核心修复] 同步全局扫描变量，并刷新战术面板的最底层！
            g_scan_freq = khz
            OLED_print_num(7, "FREQ: ", khz)
        else
            print(">> [致命错误] SX1262 拒绝了 FREQ 指令！")
            OLED_print(6, "FREQ FAIL!  ")
        end

    -- 2. [密码爆破]: SYNC 3444 (十六进制同步字)
    elseif StackStr_startswith(cmd_str, "SYNC ") then
        local sync_val = StackStr_parse_hex(cmd_str, 5)
        local s1 = (sync_val >> 8) & 255
        local s2 = sync_val & 255
        
        if C_ESP_IDF.l2c_sx1262_wait_busy() then
            C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
            C_ESP_IDF.l2c_sx1262_spi_xfer_2b(0x80, 0x00) 
            C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
        end
        C_ESP_IDF.vTaskDelay(1)
        
        local buf_sync = L2C_Buffer(5)
        C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_sync), 0, 0x0D) -- WriteReg
        C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_sync), 1, 0x07) 
        C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_sync), 2, 0x40) 
        C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_sync), 3, s1) 
        C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_sync), 4, s2) 
        
        if C_ESP_IDF.l2c_sx1262_wait_busy() then
            C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
            C_ESP_IDF.l2c_sx1262_spi_write_buffer(L2C_Ref(buf_sync), 5)
            C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
        end
        
        print(">> [成功] 同步字密码已重载为: ", sync_val)
        OLED_print(6, "SYNC Set OK")
        SX1262_restart_rx_safe(1)

    -- 3. [扩频因子调整]: SF 11
    elseif StackStr_startswith(cmd_str, "SF ") then
        local sf = StackStr_parse_int(cmd_str, 3)
        if sf >= 5 and sf <= 12 then
            -- 切换到待机模式才能配置
            if C_ESP_IDF.l2c_sx1262_wait_busy() then
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
                C_ESP_IDF.l2c_sx1262_spi_xfer_2b(0x80, 0x00) 
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
            end
            C_ESP_IDF.vTaskDelay(1) 
            
            -- SetModulationParams: 0x8B, SF, BW(0x05=250kHz), CR(0x01=4/5), LDRO(0x00)
            -- (这里默认固定了带宽 250kHz，如果想改 BW，也可以照猫画虎抽出来)
            SX1262_send_cmd5(0x8B, sf, 0x05, 0x01, 0x00)
            
            print(">> [成功] 扩频因子已重载为: SF", sf)
            OLED_print(6, "SF Set OK")
            SX1262_restart_rx_safe(1)
        else
            print(">> [错误] SF 值无效 (5~12)")
        end

    -- 4. [主动开火]: TX Hello (全息伪装注入模式！)
    elseif StackStr_startswith(cmd_str, "TX ") then
        if g_is_scanning then
            g_is_scanning = false
            print(">> [RADAR] 战术开火介入，强制挂起自动扫频！")
            OLED_print(6, "SCAN: OFF   ")
        end
        
        -- 核心：调动 C 引擎，将纯文本编译为加密装甲包！
        local out_pkt_buf = L2C_Buffer(256)
        local out_pkt_str = L2C_Ref(out_pkt_buf)
        local final_len = C_ESP_IDF.l2c_mesh_encode_text_to_str(cmd_str, 3, out_pkt_str)
        
        if final_len > 0 then
            print(">> [INJECT] 已生成全息伪装包，加密长度: ", final_len, " 字节")
            
            -- 1. 切换到 STDBY 模式
            if C_ESP_IDF.l2c_sx1262_wait_busy() then
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
                C_ESP_IDF.l2c_sx1262_spi_xfer_2b(0x80, 0x00) 
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
            end
            C_ESP_IDF.vTaskDelay(1)
            
            -- 2. 设置包参数 (注意：负载长度必须是加密后的 final_len！)
            local buf_pkt = L2C_Buffer(7)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pkt), 0, 0x8C)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pkt), 1, 0x00)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pkt), 2, 0x10) 
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pkt), 3, 0x00) 
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pkt), 4, final_len) -- [核心动态适配]
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pkt), 5, 0x01) 
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pkt), 6, 0x00) 
            if C_ESP_IDF.l2c_sx1262_wait_busy() then
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
                C_ESP_IDF.l2c_sx1262_spi_write_buffer(L2C_Ref(buf_pkt), 7)
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
            end

            -- 3. 重置收发基址到 0 (0x8F)
            local buf_base = L2C_Buffer(3)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_base), 0, 0x8F)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_base), 1, 0x00)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_base), 2, 0x00)
            if C_ESP_IDF.l2c_sx1262_wait_busy() then
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
                C_ESP_IDF.l2c_sx1262_spi_write_buffer(L2C_Ref(buf_base), 3)
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
            end

            -- 开启 PA 功放并配平发射功率
            local buf_pa = L2C_Buffer(5)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pa), 0, 0x95) 
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pa), 1, 0x02) 
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pa), 2, 0x02) 
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pa), 3, 0x00) 
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pa), 4, 0x01) 
            if C_ESP_IDF.l2c_sx1262_wait_busy() then
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
                C_ESP_IDF.l2c_sx1262_spi_write_buffer(L2C_Ref(buf_pa), 5)
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
            end
            
            local buf_txp = L2C_Buffer(3)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_txp), 0, 0x8E) 
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_txp), 1, 0x0E) -- 14dBm
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_txp), 2, 0x04) 
            if C_ESP_IDF.l2c_sx1262_wait_busy() then
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
                C_ESP_IDF.l2c_sx1262_spi_write_buffer(L2C_Ref(buf_txp), 3)
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
            end

            -- 开启中断监听 (TxDone & RxDone)
            local buf_irq = L2C_Buffer(9)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_irq), 0, 0x08)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_irq), 1, 0x00)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_irq), 2, 0x7F)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_irq), 3, 0x00)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_irq), 4, 0x7F)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_irq), 5, 0x00)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_irq), 6, 0x00) 
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_irq), 7, 0x00)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_irq), 8, 0x00) 
            if C_ESP_IDF.l2c_sx1262_wait_busy() then
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
                C_ESP_IDF.l2c_sx1262_spi_write_buffer(L2C_Ref(buf_irq), 9)
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
            end

            -- 4. 0-GC 将加密包裹压入射频 FIFO (偏移 0！)
            if C_ESP_IDF.l2c_sx1262_wait_busy() then
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
                C_ESP_IDF.l2c_sx1262_write_payload_from_str(out_pkt_str, 0)
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
            end

            -- 5. 触发发射! (0x83)
            local buf_tx = L2C_Buffer(4)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_tx), 0, 0x83)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_tx), 1, 0x00)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_tx), 2, 0x00)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_tx), 3, 0x00)
            if C_ESP_IDF.l2c_sx1262_wait_busy() then
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
                C_ESP_IDF.l2c_sx1262_spi_write_buffer(L2C_Ref(buf_tx), 4)
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
            end
            
            print(">> 载荷已发射！预计空中飞行时间 300ms... 等待 TxDone")
            OLED_print(6, "TX FIRE!    ")
        end
    elseif StackStr_startswith(cmd_str, "SCAN") then
        g_is_scanning = not g_is_scanning
        if g_is_scanning then
            print(">> [RADAR] 自动扫频模式 已开启！")
            OLED_print(4, "SCAN: ON    ")
        else
            print(">> [RADAR] 自动扫频模式 已停止。")
            OLED_print(4, "SCAN: OFF   ")
        end
        return
    -- 5. [网关配置]: WIFI 热点名 密码
    elseif StackStr_startswith(cmd_str, "WIFI ") then
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
            
            -- 0-GC 游标提取 SSID
            for i = 5, space_idx - 1 do
                StackStr_append_char(ssid_str, 64, C_ESP_IDF.l2c_get_byte(cmd_str, 1 + i))
            end
            -- 0-GC 游标提取 PASSWORD
            for i = space_idx + 1, cmd_len - 1 do
                StackStr_append_char(pwd_str, 64, C_ESP_IDF.l2c_get_byte(cmd_str, 1 + i))
            end
            
            print(">> [WIFI] 收到新热点配置: ", StackStr_get(ssid_str))
            
            -- 物理扰乱！
            NVS_Cipher_StackStr(ssid_str)
            NVS_Cipher_StackStr(pwd_str)
            
            -- 砸入底层 NVS
            C_NVS.l2c_nvs_set_stackstr("w_ssid", ssid_str)
            C_NVS.l2c_nvs_set_stackstr("w_pwd", pwd_str)
            
            print(">> [WIFI] 凭据已加密打入 NVS 黑匣子！下次重启将连接此热点。")
            OLED_print(6, "WIFI SAVED! ")
        else
            print(">> [错误] 格式不对！请使用: WIFI <SSID> <PASSWORD>")
        end
    else
        print(">> [错误] 未知战术指令！")
        OLED_print(6, "Unknown CMD!")
    end
end

-- 为 UART 和 BLE 各准备一个解析缓冲，物理隔离防止乱码串台！
local uart_buf = L2C_Buffer(64)
local ble_buf = L2C_Buffer(64)
local uart_str = L2C_Ref(uart_buf)
local ble_str = L2C_Ref(ble_buf)
StackStr_init(uart_str)
StackStr_init(ble_str)

-- [新增] 全局 0-GC 射频接收缓冲池 (256 字节防溢出)
local rx_payload_buf = L2C_Buffer(256)
local rx_payload_str = L2C_Ref(rx_payload_buf)
StackStr_init(rx_payload_str)

local scan_hold_ticks = 0 -- [核心新增] 猎犬屏息倒计时器

-- =======================================================
-- 开机自治引擎启动：提取加密 Wi-Fi 凭证！
-- =======================================================

-- 注意：WiFi 初始化极度依赖 NVS，所以必须在 NVS_init 之后调用！
local w_ssid_buf = L2C_Buffer(64); local w_ssid_str = L2C_Ref(w_ssid_buf)
local w_pwd_buf  = L2C_Buffer(64); local w_pwd_str  = L2C_Ref(w_pwd_buf)

if C_NVS.l2c_nvs_get_stackstr("w_ssid", w_ssid_str, 64) == 1 and 
   C_NVS.l2c_nvs_get_stackstr("w_pwd", w_pwd_str, 64) == 1 then
    
    -- 将 NVS 里取出的乱码进行 XOR 对称还原！
    NVS_Cipher_StackStr(w_ssid_str)
    NVS_Cipher_StackStr(w_pwd_str)
    
    local WIFI_SSID = StackStr_get(w_ssid_str)
    local WIFI_PASS = StackStr_get(w_pwd_str)

    WIFI_init_sta(WIFI_SSID, WIFI_PASS)
    OLED_print(7, "WiFi: Connecting...")

    print(" [WiFi] 密文凭证提取成功！正在启动自治连接引擎: ", WIFI_SSID)
else
    print(" [WiFi] NVS 黑匣子内无凭据。Wi-Fi 引擎已挂起，请用WIFI指令注入。")
end

-- 准备一块 0-GC 栈内存，专门用来提取 IP 地址
local ip_buf = L2C_Buffer(64)
local ip_str = L2C_Ref(ip_buf)

-- 记录网络状态机标志位
local was_connected = false

local MAC_C2_IP = "192.168.234.110"  -- 您的 Mac 真实 IP
local C2_PORT = 8888
local heartbeat_ticks = 0

while true do
    local wake_reason = 1
    
    -- 如果开启了扫描，则最多只等 150ms；否则死等
    if g_is_scanning then
        wake_reason = C_ESP_IDF.l2c_wait_for_radio_ms(150)
    else
        -- [战术神经激活] 绝对不能死等！
        -- 哪怕静默监听，最多睡 50ms (20Hz 刷新率) 必须醒来查收 Mac 空降的 UDP 密令！
        -- C_ESP_IDF.l2c_wait_for_radio()
        wake_reason = C_ESP_IDF.l2c_wait_for_radio_ms(50)
    end
    
    -- 【扫频逻辑引擎：带屏息防御】
    if wake_reason == 0 and g_is_scanning then
        if scan_hold_ticks > 0 then
            -- 猎犬正在屏息！听到前导码了，死咬住频率不放！
            scan_hold_ticks = scan_hold_ticks - 1
        else
            -- 正常切频 (每次步进 125kHz)
            g_scan_freq = g_scan_freq + 25
            if g_scan_freq > 483000 then g_scan_freq = 470000 end 
            
            local reg = C_ESP_IDF.l2c_sx1262_calc_freq(g_scan_freq)
            local b0 = (reg >> 24) & 255; local b1 = (reg >> 16) & 255
            local b2 = (reg >> 8) & 255;  local b3 = reg & 255
            
            if C_ESP_IDF.l2c_sx1262_wait_busy() then
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
                C_ESP_IDF.l2c_sx1262_spi_xfer_2b(0x80, 0x00) 
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
            end
            C_ESP_IDF.vTaskDelay(1)
            SX1262_send_cmd5(0x86, b0, b1, b2, b3)
            SX1262_restart_rx_safe(1)
            
            OLED_print_num(6, "SWEEP: ", g_scan_freq)
        end
    end
    
    -- 【业务层统筹：获取射频战果】
    local hit, irq_high, irq_low = SX1262_poll_rx(rx_payload_str)
    if hit then
        -- [新增] 核心判断 1：是否是 TxDone (发射成功！)
        if (irq_low & 1) == 1 then
            print(" [L2C-TX] 炮弹已出膛！(TxDone)")
            OLED_print(6, "TX SUCCESS! ")
            
            -- 向 Mac 战术中心发射捷报！
            local tx_rep_buf = L2C_Buffer(64); local tx_rep_str = L2C_Ref(tx_rep_buf); StackStr_init(tx_rep_str)
            StackStr_append_str(tx_rep_str, 64, "[TX DONE] 射击完毕，载荷已成功打入天空！")
            UDP_send(MAC_C2_IP, C2_PORT, StackStr_get(tx_rep_str), StackStr_len(tx_rep_str))

        -- 核心判断：是否是 RxDone (接收成功终端态)
        elseif (irq_low & 2) == 2 then
            scan_hold_ticks = 0 -- 收到完整数据，取消屏息
            
            -- 猎物彻底锁定！关闭扫描引擎！
            if g_is_scanning then
                g_is_scanning = false
                OLED_print_num(6, "LOCKED: ", g_scan_freq)
                print("========================================")
                print(" [TARGET LOCKED] 雷达已锁定频道: ", g_scan_freq, " kHz!!!")
                print("========================================")
            end
            
            OLED_clear_3to6()
            local len = StackStr_len(rx_payload_str)
            local rx_text = StackStr_get(rx_payload_str)
            
            if len >= 16 then
                local m_to = C_ESP_IDF.l2c_mesh_get_to(rx_payload_str)
                local m_from = C_ESP_IDF.l2c_mesh_get_from(rx_payload_str)
                local m_id = C_ESP_IDF.l2c_mesh_get_id(rx_payload_str)
                
                print("\n================  战术情报截获  ================")
                print(" 来源 (FROM) : ", m_from)
                
                -- 分配 0-GC 栈内存用于存放解密出的明文！
                local text_buf = L2C_Buffer(256)
                local text_str = L2C_Ref(text_buf)
                StackStr_init(text_str)
                
                -- 呼叫 AES 破壁与 Protobuf 解码引擎！
                local dec_st = C_ESP_IDF.l2c_mesh_decode_text(rx_payload_str, text_str)
                
                if dec_st == 1 then
                    local msg = StackStr_get(text_str)
                    print(" [TEXT 明文] >> ", msg)
                    OLED_print(3, ">> TEXT DECODED!")
                    OLED_print(4, msg)
                    
                    -- [修复] 将真正的明文情报写入黑匣子，绝对拒绝二进制污染！
                    local log_buf = L2C_Buffer(256)
                    local log_str = L2C_Ref(log_buf)
                    StackStr_init(log_str)

                    -- 时间戳物理注入：用隔离缓冲接住 NTP 的覆写，防止吃字
                    local time_buf = L2C_Buffer(32)
                    local time_str = L2C_Ref(time_buf)
                    StackStr_init(time_str)
                    NTP_get_time_str(time_str)

                    -- 安全拼接进日志大缸
                    StackStr_append_char(log_str, 256, 91) -- 写入 '['
                    StackStr_append_str(log_str, 256, StackStr_get(time_str))
                    StackStr_append_char(log_str, 256, 93) -- 写入 ']'

                    StackStr_append_str(log_str, 256, "[TEXT] FROM: ")
                    StackStr_append_int(log_str, 256, m_from)
                    StackStr_append_str(log_str, 256, " MSG: ")
                    StackStr_append_str(log_str, 256, msg)
                    SDCard_append("radar.log", StackStr_get(log_str))
                    
                    UDP_send(MAC_C2_IP, C2_PORT, StackStr_get(log_str), StackStr_len(log_str))
                    
                    print(" [UDP] 日志已飞向指挥中心！")

                elseif dec_st == 3 then
                    print(" [POSITION] 拦截到目标的 GPS 坐标包！")
                    OLED_print(3, ">> GPS POSITION")
                    
                    -- [扩充] 记录定位事件到黑匣子
                    local log_buf = L2C_Buffer(128)
                    local log_str = L2C_Ref(log_buf)
                    StackStr_init(log_str)

                    -- [修复] 使用时间缓冲杯，绝对防止吃字！
                    local time_buf = L2C_Buffer(32)
                    local time_str = L2C_Ref(time_buf)
                    StackStr_init(time_str)
                    NTP_get_time_str(time_str)

                    StackStr_append_char(log_str, 128, 91) 
                    StackStr_append_str(log_str, 128, StackStr_get(time_str))
                    StackStr_append_char(log_str, 128, 93)
                    
                    StackStr_append_str(log_str, 128, "[GPS] FROM: ")
                    StackStr_append_int(log_str, 128, m_from)
                    SDCard_append("radar.log", StackStr_get(log_str))
                    
                elseif dec_st == 4 then
                    print(" [NODE INFO] 拦截到目标的设备信息！")
                    OLED_print(3, ">> NODE INFO")
                elseif dec_st == 67 then
                    print(" [TELEMETRY] 拦截到目标的电池/遥测数据！")
                    OLED_print(3, ">> TELEMETRY")
                elseif dec_st > 0 then
                    print(" [DATA] 成功解密隐藏数据包，PortNum: ", dec_st)
                    OLED_print(3, ">> DATA PACKET")
                else
                    print(" [ERROR] (解密失败: 可能是私钥信道或干扰导致数据损坏)")
                end
                print("===================================================")
            else
                -- [双栖基站修复]：长度不足 16，说明是咱们 L2C 节点自己发的裸明文！直接提取！
                local rx_text = StackStr_get(rx_payload_str)
                print(" [L2C-RAW] 收到 L2C 战术网内部明文: ", rx_text)
                
                OLED_print(3, ">> RAW PACKET!")
                OLED_print(4, rx_text)
            end
        elseif (irq_low & 4) == 4 or (irq_low & 16) == 16 then
            -- [核心逻辑] 听到了前导码 (4) 或 报头 (16)
            if g_is_scanning then
                print(">> [RADAR] 猎犬察觉到微弱前导码！屏息锁定频率，等待完整电波降落...")
                scan_hold_ticks = 6 
            end
            -- [修复] 绝对不要在这里操作 OLED 屏幕！用 print 快速刷过，火速回去死盯 SPI！
            print(" [L2C-RADAR] 雷达状态变更！IRQ 状态 -> H: ", irq_high, " L: ", irq_low)
            
        elseif (irq_low & 64) == 64 or (irq_low & 32) == 32 then
            -- 发现 CRC 错误或 Header 损坏 (大概率是撞到了环境噪音)
            -- 立刻解除屏息，恢复残暴横扫！
            scan_hold_ticks = 0
            print(" [L2C-RADAR] 假信号 (CRC 损坏)，恢复横扫！")
        end
    end

    -- 【链路 1】：处理 UART (串口键盘) 命令
    local has_data, c = CMD_Pop()
    while has_data do
        if c == 10 or c == 13 then
            if StackStr_len(uart_str) > 0 then
                CMD_Process(uart_str)
                StackStr_clear(uart_str)
            end
        else
            StackStr_append_char(uart_str, 64, c)
        end
        has_data, c = CMD_Pop()
    end
    
    -- 【链路 2】：处理 BLE (手机蓝牙) 命令！
    local bc = BLE_pop_char()
    while bc > 0 do
        if bc == 10 or bc == 13 then
            if StackStr_len(ble_str) > 0 then
                CMD_Process(ble_str)
                StackStr_clear(ble_str)
            end
        else
            StackStr_append_char(ble_str, 64, bc)
        end
        bc = BLE_pop_char()
    end

    -- 【新增：异步网络状态显示】
    -- 这种非阻塞查询耗时不到 1 纳秒，绝对不影响射频性能！
    local is_conn = WIFI_is_connected()
    if is_conn and not was_connected then
        was_connected = true
        WIFI_get_ip_str(ip_str)
        print(" [WiFi] 连接成功！IP 分配: ", StackStr_get(ip_str))

        -- 【点燃 NTP 时间同步！】
        print(" [NTP] 正在向宇宙索要当前绝对时间...")
        NTP_init()

        -- [核心提速] 强制关闭省电模式，全功率迎接 Mac 指挥中心 UDP 空降！
        WIFI_Disable_PowerSave()

        UDP_server_init(8889) 
        print(" [UDP] 战术指令监听引擎已在 8889 端口上线！")

        -- 节点上线，主动向指挥中心发射一发信号弹进行 IP 注册！
        local boot_buf = L2C_Buffer(64); local boot_str = L2C_Ref(boot_buf); StackStr_init(boot_str)
        StackStr_append_str(boot_str, 64, "[SYSTEM] L2C Node is ONLINE and ARMED!")

        UDP_send(MAC_C2_IP, C2_PORT, StackStr_get(boot_str), StackStr_len(boot_str))

        OLED_clear_3to6()
        OLED_print(6, "IP: ")
        OLED_print(7, StackStr_get(ip_str))
    elseif not is_conn and was_connected then
        was_connected = false
        print(" [WiFi] 连接断开，后台尝试重连中...")
        OLED_clear_3to6()
        OLED_print(7, "WiFi: Disconnected")
    end

    -- 【链路 3】：处理 UDP 远程空降指令！
    local udp_buf = L2C_Buffer(128)
    local udp_str = L2C_Ref(udp_buf)
    
    if UDP_pop_cmd(udp_str, 128) then
        print(" [WIFI-UDP] 收到 Mac 指挥中心最高指令: ", StackStr_get(udp_str))
        CMD_Process(udp_str) -- 直接抛给网关路由中心执行！
    end

    -- 【链路 4】：战术心跳发生器 (每 10 秒跳动一次)
    if is_conn then
        heartbeat_ticks = heartbeat_ticks + 1
        -- [防丢包强化] 100 个 tick = 5 秒。高频心跳打穿路由器 UDP 丢包壁垒！
        if heartbeat_ticks >= 100 then
            heartbeat_ticks = 0
            
            local hb_buf = L2C_Buffer(32)
            local hb_str = L2C_Ref(hb_buf)
            StackStr_init(hb_str)
            StackStr_append_str(hb_str, 32, "[HEARTBEAT] L2C ALIVE")
            
            UDP_send(MAC_C2_IP, C2_PORT, StackStr_get(hb_str), StackStr_len(hb_str))
        end
    end
end