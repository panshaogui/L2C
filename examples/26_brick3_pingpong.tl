-- @l2c_import: std/eora_s3.tl
-- @l2c_import: std/lora_sx1262.tl

-- 第三层砖测试：CW 连续波发射（物理 RF 通路测试）
print("\n============================================")
print(">> [砖块 3/4] 最简 LoRa Ping-Pong 点对点物理层攻坚 (轮询模式)")
print("============================================")

-- =======================================================
-- 【核心】统一基带配置 (绝对物理对称与防弹隔离)
-- =======================================================
local function Config_Simple_LoRa()
    -- 1. STDBY
    if C_ESP_IDF.l2c_sx1262_wait_busy() then
        C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
        C_ESP_IDF.l2c_sx1262_spi_xfer_2b(0x80, 0x00) 
        C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
    end
    C_ESP_IDF.vTaskDelay(1)

    -- 2. LoRa Mode
    SX1262_send_cmd2(0x8A, 0x01) 
    
    -- 3. 470.375 MHz (0x1D660000)
    SX1262_send_cmd5(0x86, 0x1D, 0x66, 0x00, 0x00)
    
    -- 4. PA +22dBm (SX1262 极限输出)
    SX1262_send_cmd5(0x95, 0x04, 0x07, 0x00, 0x01)
    local buf_txp = L2C_Buffer(3)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_txp), 0, 0x8E)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_txp), 1, 0x16)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_txp), 2, 0x04)
    if C_ESP_IDF.l2c_sx1262_wait_busy() then
        C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
        C_ESP_IDF.l2c_sx1262_spi_write_buffer(L2C_Ref(buf_txp), 3)
        C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
    end

    -- 5. 调制: SF7, BW125, CR4/5
    SX1262_send_cmd5(0x8B, 0x07, 0x04, 0x01, 0x00)

    -- 6. 数据包: Pre8, Explicit, Payload4, CRC On
    local buf_pkt = L2C_Buffer(7)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pkt), 0, 0x8C)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pkt), 1, 0x00)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pkt), 2, 0x08) 
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pkt), 3, 0x00) 
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pkt), 4, 0x04) 
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pkt), 5, 0x01) 
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pkt), 6, 0x00) 
    if C_ESP_IDF.l2c_sx1262_wait_busy() then
        C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
        C_ESP_IDF.l2c_sx1262_spi_write_buffer(L2C_Ref(buf_pkt), 7)
        C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
    end

    -- 7. SyncWord: 0x1424
    local buf_sync = L2C_Buffer(5)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_sync), 0, 0x0D) 
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_sync), 1, 0x07) 
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_sync), 2, 0x40) 
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_sync), 3, 0x14) 
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_sync), 4, 0x24) 
    if C_ESP_IDF.l2c_sx1262_wait_busy() then
        C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
        C_ESP_IDF.l2c_sx1262_spi_write_buffer(L2C_Ref(buf_sync), 5)
        C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
    end

    -- 8. 接管 DIO2 (射频天线开关)
    if C_ESP_IDF.l2c_sx1262_wait_busy() then
        C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
        C_ESP_IDF.l2c_sx1262_spi_xfer_2b(0x9D, 0x01)
        C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
    end

    -- 10. 打开 IRQ 标志位总闸
    local buf_irq = L2C_Buffer(9)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_irq), 0, 0x08)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_irq), 1, 0x00)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_irq), 2, 0x7F) 
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_irq), 3, 0x00)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_irq), 4, 0x00) 
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_irq), 5, 0x00)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_irq), 6, 0x00) 
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_irq), 7, 0x00)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_irq), 8, 0x00) 
    if C_ESP_IDF.l2c_sx1262_wait_busy() then
        C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
        C_ESP_IDF.l2c_sx1262_spi_write_buffer(L2C_Ref(buf_irq), 9)
        C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
    end
end

-- =======================================================
-- 任务模式 1：发射端 (Ping)
-- =======================================================
local function Run_Transmitter()
    print(">> [TX] 启动发射机 (Ping) 模式 ...")
    Config_Simple_LoRa()

    while true do
        -- 清除 IRQ
        local buf_clr = L2C_Buffer(3)
        C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_clr), 0, 0x02)
        C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_clr), 1, 0x03)
        C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_clr), 2, 0xFF)
        if C_ESP_IDF.l2c_sx1262_wait_busy() then
            C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
            C_ESP_IDF.l2c_sx1262_spi_write_buffer(L2C_Ref(buf_clr), 3)
            C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
        end

        -- [核心修复] 基址清零 0x8F (SetBufferBaseAddress)
        local buf_base = L2C_Buffer(3)
        C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_base), 0, 0x8F) 
        C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_base), 1, 0x00)
        C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_base), 2, 0x00)
        if C_ESP_IDF.l2c_sx1262_wait_busy() then
            C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
            C_ESP_IDF.l2c_sx1262_spi_write_buffer(L2C_Ref(buf_base), 3)
            C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
        end

        -- [核心修复] 压入数据 0x0E (WriteBuffer)
        local pay = L2C_Buffer(6)
        C_ESP_IDF.l2c_set_byte(L2C_Ref(pay), 0, 0x0E)
        C_ESP_IDF.l2c_set_byte(L2C_Ref(pay), 1, 0x00)
        C_ESP_IDF.l2c_set_byte(L2C_Ref(pay), 2, 80) -- P
        C_ESP_IDF.l2c_set_byte(L2C_Ref(pay), 3, 73) -- I
        C_ESP_IDF.l2c_set_byte(L2C_Ref(pay), 4, 78) -- N
        C_ESP_IDF.l2c_set_byte(L2C_Ref(pay), 5, 71) -- G
        if C_ESP_IDF.l2c_sx1262_wait_busy() then
            C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
            C_ESP_IDF.l2c_sx1262_spi_write_buffer(L2C_Ref(pay), 6)
            C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
        end

        -- 触发发射 (0x83)
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

        print(">> [TX] 报文发射中... 轮询等待 TxDone")
        
        while true do
            local tx_st = L2C_Buffer(4)
            local rx_st = L2C_Buffer(4)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_st), 0, 0x12)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_st), 1, 0x00) 
            C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_st), 2, 0x00) 
            C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_st), 3, 0x00) 
            if C_ESP_IDF.l2c_sx1262_wait_busy() then
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
                C_ESP_IDF.l2c_sx1262_spi_transfer_safe(L2C_Ref(tx_st), L2C_Ref(rx_st), 4)
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
            end
            
            local irq_low = C_ESP_IDF.l2c_get_byte(L2C_Ref(rx_st), 3)
            if (irq_low & 1) == 1 then
                print(" [TX] 发射成功！")
                break
            end
            C_ESP_IDF.vTaskDelay(2)
        end
        
        C_ESP_IDF.vTaskDelay(200) -- 等 2 秒发下一个 (200 * 10ms = 2s)
    end
end

-- =======================================================
-- 任务模式 2：接收端 (Pong) —— 终极雷达版
-- =======================================================
local function Run_Receiver()
    print(">> [RX] 启动接收机 (Pong) 模式 ...")
    Config_Simple_LoRa()
    
    -- 切入连续接收
    local buf_rx = L2C_Buffer(4)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_rx), 0, 0x82)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_rx), 1, 0xFF)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_rx), 2, 0xFF)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_rx), 3, 0xFF)
    if C_ESP_IDF.l2c_sx1262_wait_busy() then
        C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
        C_ESP_IDF.l2c_sx1262_spi_write_buffer(L2C_Ref(buf_rx), 4)
        C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
    end

    print(">> [RX] 正在每 50ms 轮询 GetIrqStatus ...")
    
    local tick_count = 0
    while true do
        C_ESP_IDF.vTaskDelay(5) -- 歇 50ms
        tick_count = tick_count + 1
        
        -- 每 1 秒打印一次硬件心跳！
        if tick_count % 20 == 0 then
            if C_ESP_IDF.l2c_sx1262_wait_busy() then
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
                local status_val = C_ESP_IDF.l2c_sx1262_spi_xfer_2b(0xC0, 0x00)
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
                local mode = (status_val // 256 >> 4) & 7
                print(" [RX 心跳] 当前物理 Chip Mode: ", mode, " (应为 5: RX)")
            end
        end

        local tx_st = L2C_Buffer(4)
        local rx_st = L2C_Buffer(4)
        C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_st), 0, 0x12)
        C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_st), 1, 0x00) 
        C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_st), 2, 0x00) 
        C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_st), 3, 0x00) 
        if C_ESP_IDF.l2c_sx1262_wait_busy() then
            C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
            C_ESP_IDF.l2c_sx1262_spi_transfer_safe(L2C_Ref(tx_st), L2C_Ref(rx_st), 4)
            C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
        end
        
        local irq_high = C_ESP_IDF.l2c_get_byte(L2C_Ref(rx_st), 2)
        local irq_low  = C_ESP_IDF.l2c_get_byte(L2C_Ref(rx_st), 3)

        -- 只要有一丁点动静，立刻报警！
        if irq_low > 0 or irq_high > 0 then
            print(" [RX-POLL] 捕捉到硬件中断！IRQ H: ", irq_high, " L: ", irq_low)
            
            if (irq_low & 64) == 64 then
                print(" [RX] 拦截到信号，但 CRC 校验错误！")
            elseif (irq_low & 2) == 2 then
                print(" [RX] RxDone 触发！正在提取数据...")
                
                local st_rx = L2C_Buffer(4)
                C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_st), 0, 0x13)
                if C_ESP_IDF.l2c_sx1262_wait_busy() then
                    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
                    C_ESP_IDF.l2c_sx1262_spi_transfer_safe(L2C_Ref(tx_st), L2C_Ref(st_rx), 4)
                    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
                end
                
                local pay_len = C_ESP_IDF.l2c_get_byte(L2C_Ref(st_rx), 2)
                local rx_off = C_ESP_IDF.l2c_get_byte(L2C_Ref(st_rx), 3)
                
                local payload_buf = L2C_Buffer(256)
                local payload_str = L2C_Ref(payload_buf)
                StackStr_init(payload_str)
                
                if C_ESP_IDF.l2c_sx1262_wait_busy() then
                    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
                    C_ESP_IDF.l2c_sx1262_read_payload_to_str(rx_off, pay_len, payload_str)
                    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
                end

                print(" [RX] 成功收到明文报文: ", StackStr_get(payload_str))
            end

            -- 清除 IRQ
            local buf_clr = L2C_Buffer(3)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_clr), 0, 0x02)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_clr), 1, 0x03)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_clr), 2, 0xFF)
            if C_ESP_IDF.l2c_sx1262_wait_busy() then
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
                C_ESP_IDF.l2c_sx1262_spi_write_buffer(L2C_Ref(buf_clr), 3)
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
            end
        end
    end
end

SX1262_init()

print("============================================")
print(">> [砖块 3/4] 极简 LoRa Ping-Pong 对波测试 ")
print("============================================")

-- 【物理拨码开关】：在这里选择当前板子的身份！
local IS_TRANSMITTER = true 

if IS_TRANSMITTER then
    Run_Transmitter()
else
    Run_Receiver()
end
