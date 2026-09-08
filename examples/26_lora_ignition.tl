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

-- EoRa-S3 默认 OLED 引脚: SDA=18, SCL=17

OLED_init(18, 17)
OLED_clear() 

NVS_init()

local boot_count = NVS_get_int("boot_cnt", 0)
boot_count = boot_count + 1
NVS_set_int("boot_cnt", boot_count)

OLED_print(0, "L2C-Mesh Node v1.0")
OLED_print(1, "===================")
OLED_print(2, "Initializing RF...")

OLED_print_num(6, "Boot Count: ", boot_count)

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
OLED_print(7, "Sniffing 433MHz...")

print(" [L2C] 已潜入 433/470MHz 频段，系统进入静默状态...")

---------------------------------------------------------
-- 0-GC 命令路由中心！
---------------------------------------------------------

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
        else
            print(">> [致命错误] SX1262 拒绝了 FREQ 指令！")
            OLED_print(6, "FREQ Set FAIL!")
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

    -- 4. [主动开火]: TX Hello
    elseif StackStr_startswith(cmd_str, "TX ") then
        local pay_len = StackStr_len(cmd_str) - 3
        if pay_len > 0 then
            print(">> 准备发射报文，长度: ", pay_len, " 字节")
            
            -- 1. 切换到 STDBY 模式
            if C_ESP_IDF.l2c_sx1262_wait_busy() then
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
                C_ESP_IDF.l2c_sx1262_spi_xfer_2b(0x80, 0x00) 
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
            end
            C_ESP_IDF.vTaskDelay(1)
            
            -- 2. 设置包参数 (0x8C, 0, 前导码16, 显式报头0, 负载长度 pay_len, CRC开1, IQ标准0)
            local buf_pkt = L2C_Buffer(7)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pkt), 0, 0x8C)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pkt), 1, 0x00)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pkt), 2, 0x10) 
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pkt), 3, 0x00) 
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pkt), 4, pay_len) 
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pkt), 5, 0x01) 
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pkt), 6, 0x00) 
            if C_ESP_IDF.l2c_sx1262_wait_busy() then
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
                C_ESP_IDF.l2c_sx1262_spi_write_buffer(L2C_Ref(buf_pkt), 7)
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
            end

            -- 3. 重置收发基址到 0 (0x8F SetBufferBaseAddress)
            local buf_base = L2C_Buffer(3)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_base), 0, 0x8F) -- [核心修复] 0x8F 才是设基址！
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_base), 1, 0x00)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_base), 2, 0x00)
            if C_ESP_IDF.l2c_sx1262_wait_busy() then
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
                C_ESP_IDF.l2c_sx1262_spi_write_buffer(L2C_Ref(buf_base), 3)
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
            end

            -- [新增] 射频功放点火 (SetPaConfig + SetTxParams)
            -- 开启 +14dBm 安全功率，防止 OCP 过流重启 
            local buf_pa = L2C_Buffer(5)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pa), 0, 0x95) -- 0x95 PaConfig
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pa), 1, 0x02) -- paDutyCycle
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pa), 2, 0x02) -- hpMax
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pa), 3, 0x00) -- deviceSel (SX1262)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pa), 4, 0x01) -- paLdoEnable
            if C_ESP_IDF.l2c_sx1262_wait_busy() then
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
                C_ESP_IDF.l2c_sx1262_spi_write_buffer(L2C_Ref(buf_pa), 5)
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
            end
            
            local buf_txp = L2C_Buffer(3)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_txp), 0, 0x8E) -- 0x8E TxParams
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_txp), 1, 0x0E) -- TxPower: 14dBm (0x0E)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_txp), 2, 0x04) -- RampTime: 200us
            if C_ESP_IDF.l2c_sx1262_wait_busy() then
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
                C_ESP_IDF.l2c_sx1262_spi_write_buffer(L2C_Ref(buf_txp), 3)
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
            end

            -- 【核心修复 1：配置中断掩码，同时监听 TxDone(1) 和 RxDone(2) 等】
            -- 0x7F 意味着只要芯片有任何动静，都拉高 DIO1！
            local buf_irq = L2C_Buffer(9)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_irq), 0, 0x08)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_irq), 1, 0x00)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_irq), 2, 0x7F) -- IRQ Mask
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_irq), 3, 0x00)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_irq), 4, 0x7F) -- DIO1 Mask
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_irq), 5, 0x00)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_irq), 6, 0x00) 
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_irq), 7, 0x00)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_irq), 8, 0x00) 
            if C_ESP_IDF.l2c_sx1262_wait_busy() then
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
                C_ESP_IDF.l2c_sx1262_spi_write_buffer(L2C_Ref(buf_irq), 9)
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
            end

            -- 4. 0-GC 极速 Payload 压入硬件 FIFO (偏移量为 3，跳过 "TX " 字符)
            if C_ESP_IDF.l2c_sx1262_wait_busy() then
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
                C_ESP_IDF.l2c_sx1262_write_payload_from_str(cmd_str, 3)
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
            end

            -- 5. 触发发射! (0x83 SetTx)
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
            
            print(">> 报文已压入发射端！等待 TxDone 硬件中断...")
            OLED_print(6, "TX FIRE!    ")
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

while true do
    C_ESP_IDF.l2c_wait_for_radio()
    
    -- 【业务层统筹：传入 Payload 缓冲区，获取射频战果】
    local hit, irq_high, irq_low = SX1262_poll_rx(rx_payload_str)
    if hit then
        OLED_clear_3to6()
        
        -- 核心判断：是否是 RxDone (接收成功终端态，irq_low 的 Bit 1 为 1)
        if (irq_low & 2) == 2 then
            local rx_text = StackStr_get(rx_payload_str)
            print(" [L2C-RX] 战术网传回明文: ", rx_text)
            
            OLED_print(3, ">> MSG RECEIVED!")
            OLED_print(5, rx_text)
            
            -- 将明文内容写入物理黑匣子
            local log_buf = L2C_Buffer(256)
            local log_str = L2C_Ref(log_buf)
            StackStr_init(log_str)
            StackStr_append_str(log_str, 256, "[RX MSG] ")
            StackStr_append_str(log_str, 256, rx_text)
            SDCard_append("radar.log", StackStr_get(log_str))
        else
            -- 其他射频事件 (TxDone, 报头错误, CRC失败等)
            OLED_print(3, ">> RADAR EVENT")
            OLED_print_num(4, "IRQ H: ", irq_high)
            OLED_print_num(5, "IRQ L: ", irq_low)
            print(" [L2C-RADAR] 雷达状态变更！IRQ 状态 -> H: ", irq_high, " L: ", irq_low)
            
            local log_buf = L2C_Buffer(64)
            local log_str = L2C_Ref(log_buf)
            StackStr_init(log_str)
            StackStr_append_str(log_str, 64, "Event! IRQ_H: ")
            StackStr_append_int(log_str, 64, irq_high)
            StackStr_append_str(log_str, 64, " IRQ_L: ")
            StackStr_append_int(log_str, 64, irq_low)
            SDCard_append("radar.log", StackStr_get(log_str))
        end
    end

    -- 【链路 1】：处理 UART (串口键盘) 命令
    local has_data, c = CMD_Pop()
    while has_data do
        if c == 10 or c == 13 then
            if StackStr_len(uart_str) > 0 then
                -- 【直接呼叫路由中心！】
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
                -- 【直接呼叫路由中心！】
                CMD_Process(ble_str)
                StackStr_clear(ble_str)
            end
        else
            StackStr_append_char(ble_str, 64, bc)
        end
        bc = BLE_pop_char()
    end
end