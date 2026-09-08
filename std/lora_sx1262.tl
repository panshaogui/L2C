-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- std/lora_sx1262.tl
-- SX1262 0-GC 射频驱动核心 (ESP-IDF 极速 SPI 桥接)

-- @l2c_source: clib/mcu/esp32_sx1262.c
-- @l2c_import: std/eora_s3.tl
--@l2c_import: std/oled_ssd1306.tl
--@l2c_import: std/stackstring.tl

-- 1. [L2C FFI 探针]：拦截 C 宇宙的底层函数！
-- 我们利用刚刚完善的 LIR 引擎，将 any 自动降维为 void* 指针。
local type C_ESP_IDF = record
    -- 基础 GPIO 与系统延时
    gpio_set_direction: function(integer, integer)
    gpio_set_level: function(integer, integer)
    gpio_get_level: function(integer): integer
    vTaskDelay: function(integer)
    
    -- 极速 SPI 引擎接口
    l2c_sx1262_spi_init: function(integer, integer, integer)
    l2c_sx1262_spi_xfer_2b: function(integer, integer): integer

    l2c_set_byte: function(any, integer, integer)
    l2c_get_byte: function(any, integer): integer

    l2c_sx1262_spi_write_buffer: function(any, integer)

    -- [硬件中断与深渊挂起探针]
    l2c_setup_dio1_interrupt: function(integer)
    l2c_wait_for_radio: function()

    l2c_launch_core1: function(any)
    l2c_wake_main_core: function()

    l2c_sx1262_calc_freq: function(integer): integer  -- 引入频率计算器！
    l2c_sx1262_write_payload_from_str: function(any, integer)
    l2c_sx1262_read_payload_to_str: function(integer, integer, any)

    l2c_sx1262_set_busy_pin: function(integer)
    l2c_sx1262_wait_busy: function(): boolean  -- [新增] FFI: 物理防线探针
    l2c_sx1262_spi_transfer_safe: function(any, any, integer): integer
end

-- 2. 硬件复位与唤醒引擎 (时序极其严苛)
local function SX1262_hw_reset()
    print("[SX1262] 正在执行硬件物理复位...")
    C_ESP_IDF.gpio_set_direction(EORA_BOARD.RST, GPIO_MODE_OUTPUT)
    
    C_ESP_IDF.gpio_set_level(EORA_BOARD.RST, 0)
    C_ESP_IDF.vTaskDelay(2)
    
    C_ESP_IDF.gpio_set_level(EORA_BOARD.RST, 1)
    C_ESP_IDF.vTaskDelay(2) 
    
    -- 【核心修复：注入物理唤醒脉冲 (Wakeup)】
    print("[SX1262] 发送 CS 唤醒脉冲...")
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
    C_ESP_IDF.vTaskDelay(1) -- 拉低一段时间踢醒芯片
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
    C_ESP_IDF.vTaskDelay(1) -- 稍作等待
    
    print("[SX1262] 等待芯片 BUSY 引脚释放...")
    C_ESP_IDF.gpio_set_direction(EORA_BOARD.BUSY, GPIO_MODE_INPUT)
    
    while C_ESP_IDF.gpio_get_level(EORA_BOARD.BUSY) == 1 do
        -- 芯片醒来并准备好后，BUSY 会自动变低
    end
    print("[SX1262] 芯片已彻底苏醒并就绪！")
end

-- 3. 极速命令探针 (测试 SPI 通讯)
local function SX1262_read_status()
    -- CS 拉低，独占总线
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
    
    -- 发送 0xC0 (GetStatus) 和 0x00 (NOP)
    local rx_val = C_ESP_IDF.l2c_sx1262_spi_xfer_2b(0xC0, 0x00)
    
    -- CS 拉高，释放总线
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
    
    -- 位运算解包：高 8 位是 Byte 0，低 8 位是 Byte 1
    local b0 = rx_val // 256
    local b1 = rx_val & 255
    
    print("[SX1262] 原始 SPI 接收 - Byte 0: ", b0, " Byte 1: ", b1)
    
end

local function SX1262_init()
    print("[SX1262] 正在初始化 SPI 射频总线...")

    -- CS 片选引脚初始化为高电平
    C_ESP_IDF.gpio_set_direction(EORA_BOARD.CS, GPIO_MODE_OUTPUT)
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
    
    -- 触发底层的 C 语言 SPI 硬件初始化
    C_ESP_IDF.l2c_sx1262_spi_init(EORA_BOARD.SCK, EORA_BOARD.MISO, EORA_BOARD.MOSI)
    
    -- 【关键对接：把 BUSY 引脚的物理地址告诉 C 语言防弹衣！】
    C_ESP_IDF.l2c_sx1262_set_busy_pin(EORA_BOARD.BUSY)

    SX1262_hw_reset()
    
    SX1262_read_status()

    print("[SX1262] 开始配置射频基带 (无源晶振模式)...")
    
    -- 1. [极其重要] 设置为 STDBY_RC 模式，进入配置状态
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
    C_ESP_IDF.l2c_sx1262_spi_xfer_2b(0x80, 0x00) 
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
    C_ESP_IDF.vTaskDelay(1) 

    -- 2. [情报应用] 让 SX1262 自动接管天线射频开关 (DIO2)
    -- 指令格式: 0x9D, enable(0x01)
    print("[SX1262] 正在接管天线射频开关 (DIO2)...")
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
    C_ESP_IDF.l2c_sx1262_spi_xfer_2b(0x9D, 0x01)
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
    
    print("[SX1262] 射频基带配置完毕，XTAL 晶振准备就绪！")
end

---------------------------------------------------------
-- 4. 射频参数配置与发射引擎 (0-GC 物理封装)
---------------------------------------------------------

-- 底层多参指令发送器（带硬件安全断言）
local function SX1262_send_cmd2(cmd: integer, a1: integer): boolean
    local tx_buf = L2C_Buffer(2)
    local rx_buf = L2C_Buffer(2)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_buf), 0, cmd)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_buf), 1, a1)
    
    if not C_ESP_IDF.l2c_sx1262_wait_busy() then return false end -- [修复] NSS拉低前必须探测BUSY
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
    local st = C_ESP_IDF.l2c_sx1262_spi_transfer_safe(L2C_Ref(tx_buf), L2C_Ref(rx_buf), 2)
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
    return st >= 0
end

local function SX1262_send_cmd5(cmd: integer, a1: integer, a2: integer, a3: integer, a4: integer): boolean
    local tx_buf = L2C_Buffer(5)
    local rx_buf = L2C_Buffer(5)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_buf), 0, cmd)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_buf), 1, a1)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_buf), 2, a2)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_buf), 3, a3)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_buf), 4, a4)
    
    if not C_ESP_IDF.l2c_sx1262_wait_busy() then return false end
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
    local st = C_ESP_IDF.l2c_sx1262_spi_transfer_safe(L2C_Ref(tx_buf), L2C_Ref(rx_buf), 5)
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
    return st >= 0
end

local function SX1262_send_cmd9(cmd: integer, a1: integer, a2: integer, a3: integer, a4: integer, a5: integer, a6: integer, a7: integer, a8: integer): boolean
    local tx_buf = L2C_Buffer(9)
    local rx_buf = L2C_Buffer(9)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_buf), 0, cmd)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_buf), 1, a1)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_buf), 2, a2)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_buf), 3, a3)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_buf), 4, a4)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_buf), 5, a5)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_buf), 6, a6)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_buf), 7, a7)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_buf), 8, a8)

    if not C_ESP_IDF.l2c_sx1262_wait_busy() then return false end
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
    local st = C_ESP_IDF.l2c_sx1262_spi_transfer_safe(L2C_Ref(tx_buf), L2C_Ref(rx_buf), 9)
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
    return st >= 0
end

-- 寄存器写入函数 (0x0D WriteRegister)
local function SX1262_write_register(reg: integer, val: integer): boolean
    local tx_buf = L2C_Buffer(4)
    local rx_buf = L2C_Buffer(4)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_buf), 0, 0x0D)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_buf), 1, (reg >> 8) & 0xFF)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_buf), 2, reg & 0xFF)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_buf), 3, val)

    if not C_ESP_IDF.l2c_sx1262_wait_busy() then return false end
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
    local st = C_ESP_IDF.l2c_sx1262_spi_transfer_safe(L2C_Ref(tx_buf), L2C_Ref(rx_buf), 4)
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
    return st >= 0
end

-- 闭环模式状态反查校验: 反查芯片 Mode 是否匹配预期
local function SX1262_verify_chip_mode(expected_mode: integer): boolean
    local tx_buf = L2C_Buffer(2)
    local rx_buf = L2C_Buffer(2)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_buf), 0, 0xC0) -- GetStatus
    C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_buf), 1, 0x00)

    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
    local st = C_ESP_IDF.l2c_sx1262_spi_transfer_safe(L2C_Ref(tx_buf), L2C_Ref(rx_buf), 2)
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)

    if st < 0 then return false end

    local raw_status = C_ESP_IDF.l2c_get_byte(L2C_Ref(rx_buf), 0)
    local current_mode = (raw_status >> 4) & 0x07
    return current_mode == expected_mode
end

-- 【升级版】带重试与物理 Chip Mode 验证的重启 RX 函数
local function SX1262_restart_rx_safe(max_retries: integer): boolean
    local retry_cnt = max_retries or 3
    
    while retry_cnt > 0 do
        -- 1. 发送 SetRx (0x82) 指令 (超时设为 0xFFFFFF 连续监听)
        local tx_buf = L2C_Buffer(4)
        local rx_buf = L2C_Buffer(4)
        C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_buf), 0, 0x82)
        C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_buf), 1, 0xFF)
        C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_buf), 2, 0xFF)
        C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_buf), 3, 0xFF)

        C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
        local st = C_ESP_IDF.l2c_sx1262_spi_transfer_safe(L2C_Ref(tx_buf), L2C_Ref(rx_buf), 4)
        C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)

        -- 2. 只有 SPI 传输成功且 Status Byte 无拒收错误时，才去校验 Chip Mode
        if st >= 0 then
            -- 检查 0xC0 GetStatus 反查 Chip Mode 是否已成功切换为 0x5 (RX)
            if SX1262_verify_chip_mode(5) then
                return true -- 闭环验证成功：芯片已真实处于 RX 监听状态！
            end
        end

        -- 如果因为 BUSY 延迟或状态机未就绪失败，短暂等待后重试
        retry_cnt = retry_cnt - 1
        print("[SX1262-WARN] 切 RX 失败/BUSY 占用，正在进行重试... 剩余次数: ", retry_cnt)
    end

    return false -- 多次重试均失败
end

-- 配置 CN470 与 Meshtastic LongFast 监听参数
local function SX1262_setup_meshtastic_sniffer(): boolean
    print("[SX1262] 切入 Meshtastic 窃听模式...")

    -- 初始化物理 BUSY 引脚拦截
    C_ESP_IDF.l2c_sx1262_set_busy_pin(EORA_BOARD.BUSY)

    -- 0. 切入 Standby RC 模式 (0x80, 0x00) 以允许配置修改
    if not SX1262_send_cmd2(0x80, 0x00) then
        print("[SX1262-ERR] 无法切入 Standby 模式！")
        return false
    end

    -- 1. 切换为 Packet Type: LoRa 模式 (0x8A, 0x01)
    if not SX1262_send_cmd2(0x8A, 0x01) then
        print("[SX1262-ERR] 无法配置 PacketType 为 LoRa！")
        return false
    end

    -- 2. 设置 RF 频率为中国区 CN470 默认主频 470.375 MHz
    -- 利用 L2C 64位引擎进行雷达动态调频 (470.375 MHz)
    print("[SX1262] 动态计算并锁定 CN 频道 470.375 MHz...")
    local freq_reg = C_ESP_IDF.l2c_sx1262_calc_freq(470375)
    local f1 = (freq_reg >> 24) & 0xFF
    local f2 = (freq_reg >> 16) & 0xFF
    local f3 = (freq_reg >> 8) & 0xFF
    local f4 = freq_reg & 0xFF
    if not SX1262_send_cmd5(0x86, f1, f2, f3, f4) then
        print("[SX1262-ERR] 频率设置失败 (470.375MHz)！")
        return false
    end

    -- 3. 设置调制参数 (SetModulationParams - 0x8B)
    -- 参数项: SF11 (0x0B), BW 250kHz (0x05), CR 4/5 (0x01), LowDataRateOptimize ON (0x01)
    -- 注: SF11 在 250kHz 下必须开启 LowDataRateOptimize (第4位设为 0x01)，否则解调率极大下降！
    print("[SX1262] 锁定基带: SF11, BW250, CR4/5, LDRO=ON...")
    if not SX1262_send_cmd5(0x8B, 0x0B, 0x05, 0x01, 0x01) then
        print("[SX1262-ERR] 调制参数配置被拒！")
        return false
    end

    -- 4. 写入 Meshtastic 专属 LoRa SyncWord (0x2B44)
    -- Meshtastic 官方网络使用了 0x2B44 (Private Network SyncWord)
    -- Reg 0x0740 -> 0x2B, Reg 0x0741 -> 0x44
    print("[SX1262] 注入 Meshtastic 专属 SyncWord (0x2B44)...")
    SX1262_write_register(0x0740, 0x2B)
    SX1262_write_register(0x0741, 0x44)

    -- 5. 设置数据包参数 (SetPacketParams - 0x8C)
    -- 0x00, 0x10 : Preamble 长度 = 16 码片 (Meshtastic 默认 16)
    -- 0x00       : HeaderType = Explicit (显式报头)
    -- 0xFF       : Payload Length = 255 (最大变长接收)
    -- 0x01       : CRCType = CRC ON
    -- 0x00       : Standard IQ (非反转)
    print("[SX1262] 配置 PacketParams (Preamble=16, Explicit, MaxLen=255, CRC=ON)...")
    if not SX1262_send_cmd9(0x8C, 0x00, 0x10, 0x00, 0xFF, 0x01, 0x00, 0x00, 0x00) then
        print("[SX1262-ERR] 数据包结构参数设置失败！")
        return false
    end

    -- 6. 开启 RX 硬件中断映射 (SetDioIrqParams - 0x08)
    -- 映射 RxDone (Bit 1) 到 DIO1
    SX1262_send_cmd9(0x08, 0x02, 0x02, 0x02, 0x02, 0x00, 0x00, 0x00, 0x00)

    -- 7. 闭环启动连续接收模式 (SetRx Continuous)
    print("[SX1262] 启动 RX 连续监听状态闭环验证...")
    if SX1262_restart_rx_safe(1) then
        print(">> [成功] SX1262 已开启 Meshtastic CN470 (470.375MHz) 硬件监听！")
        return true
    else
        print(">> [致命错误] SX1262 无法保持在 RX 模式！")
        return false
    end
end

-- 切入连续监听模式
local function SX1262_setup_rx()
    print("[SX1262] 正在设置全频段雷达中断矩阵...")
    local buf_irq = L2C_Buffer(9)
    local p_irq = L2C_Ref(buf_irq)
    C_ESP_IDF.l2c_set_byte(p_irq, 0, 0x08) -- SetDioIrqParams
    
    -- 【核心调整：捕获一切动静！】
    -- 0x007E = RxDone(0x02)|Preamble(0x04)|SyncWord(0x08)|HeaderValid(0x10)|HeaderErr(0x20)|CrcErr(0x40)
    C_ESP_IDF.l2c_set_byte(p_irq, 1, 0x00)
    C_ESP_IDF.l2c_set_byte(p_irq, 2, 0x7E) -- IRQ Mask
    C_ESP_IDF.l2c_set_byte(p_irq, 3, 0x00)
    C_ESP_IDF.l2c_set_byte(p_irq, 4, 0x7E) -- DIO1 Mask
    
    C_ESP_IDF.l2c_set_byte(p_irq, 5, 0x00)
    C_ESP_IDF.l2c_set_byte(p_irq, 6, 0x00) -- DIO2 Mask
    C_ESP_IDF.l2c_set_byte(p_irq, 7, 0x00)
    C_ESP_IDF.l2c_set_byte(p_irq, 8, 0x00) -- DIO3 Mask
    
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
    C_ESP_IDF.l2c_sx1262_spi_write_buffer(p_irq, 9)
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)

    print("[SX1262] 雷达开启，进入连续接收模式...")
    local buf_rx = L2C_Buffer(4)
    local p_rx = L2C_Ref(buf_rx)
    C_ESP_IDF.l2c_set_byte(p_rx, 0, 0x82)
    C_ESP_IDF.l2c_set_byte(p_rx, 1, 0xFF)
    C_ESP_IDF.l2c_set_byte(p_rx, 2, 0xFF)
    C_ESP_IDF.l2c_set_byte(p_rx, 3, 0xFF)
    
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
    C_ESP_IDF.l2c_sx1262_spi_write_buffer(p_rx, 4)
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
end

-- 轮询 DIO1 中断并提取报文 (纯物理层探针)
-- @param payload_buf: 外层传入的 StackString 缓冲区，用于零拷贝提取报文
-- 返回 boolean (是否触发), high, low。绝对不要在这里碰屏幕 (OLED 阻塞 = 丢包)！
local function SX1262_poll_rx(payload_buf: any): boolean, integer, integer
    if C_ESP_IDF.gpio_get_level(EORA_BOARD.DIO1) == 1 then
        
        -- 1. 获取引发中断的真实原因 (0x12 GetIrqStatus)
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
        
        -- 提取 16位 的 IRQ 状态码
        local irq_high = C_ESP_IDF.l2c_get_byte(L2C_Ref(rx_st), 2)
        local irq_low  = C_ESP_IDF.l2c_get_byte(L2C_Ref(rx_st), 3)
        
        -- 清除所有硬件中断标志位
        local buf_clr = L2C_Buffer(3)
        C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_clr), 0, 0x02)
        C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_clr), 1, 0x03)
        C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_clr), 2, 0xFF)
        
        if C_ESP_IDF.l2c_sx1262_wait_busy() then
            C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
            C_ESP_IDF.l2c_sx1262_spi_write_buffer(L2C_Ref(buf_clr), 3)
            C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
        end
        
        -- 【终极防御：判定是否到达终态】
        local is_terminal_state = false

        if (irq_low & 1) == 1 then
            print(" [L2C-TX] 报文物理发射完毕 (TxDone)！")
            is_terminal_state = true
        elseif (irq_low & 2) == 2 then
            -- RxDone (接收成功)
            local st_rx = L2C_Buffer(4)
            C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_st), 0, 0x13)
            
            if C_ESP_IDF.l2c_sx1262_wait_busy() then
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
                C_ESP_IDF.l2c_sx1262_spi_transfer_safe(L2C_Ref(tx_st), L2C_Ref(st_rx), 4)
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
            end
            
            local payload_len = C_ESP_IDF.l2c_get_byte(L2C_Ref(st_rx), 2)
            local rx_offset = C_ESP_IDF.l2c_get_byte(L2C_Ref(st_rx), 3)
            
            if C_ESP_IDF.l2c_sx1262_wait_busy() then
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
                C_ESP_IDF.l2c_sx1262_read_payload_to_str(rx_offset, payload_len, payload_buf)
                C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
            end

            print(" [L2C-RX] 核心引擎捕获数据，耗时极短 (len: ", payload_len, ")")
            is_terminal_state = true
        elseif (irq_low & 64) == 64 then
            print(" [L2C-RX] CRC 校验错误！")
            is_terminal_state = true
        elseif (irq_low & 32) == 32 then
            print(" [L2C-RX] 报文头损坏！")
            is_terminal_state = true
        else
            -- 仅仅是听到了前导码 (IRQ L: 4) 等非终态事件，绝对不干预！
            print(" [L2C-RADAR] 锁定信号中... (IRQ L: ", irq_low, ")")
        end
        
        -- 【核心解法】：只有芯片完成了发射，或者接收以失败/成功彻底结束，我们才重启 RX 模式！
        if is_terminal_state then
            -- [升级防护] 采用强校验闭环重启 RX 模式
            local rx_ok = SX1262_restart_rx_safe(3) -- 允许最多重试 3 次（防 BUSY 锁死）
            
            if not rx_ok then
                print("[SX1262-ERR] 终端状态重启 RX 失败！执行软复位兜底...")
                -- 如果多次重试切 RX 仍然失败，执行强制初始化防护
                -- SX1262_setup_meshtastic_sniffer()
            end
        end
        
        return true, irq_high, irq_low
    end
    
    return false, 0, 0
end