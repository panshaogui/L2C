-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- std/lora_sx1262.tl
-- SX1262 0-GC 射频驱动核心 (ESP-IDF 极速 SPI 桥接)

-- @l2c_import: std/eora_s3.tl
-- @l2c_import: std/oled_ssd1306.tl
-- @l2c_source: clib/mcu/esp32_sx1262.c

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
    l2c_sx1262_spi_transfer: function(any, any, integer)

    l2c_set_byte: function(any, integer, integer)
    l2c_get_byte: function(any, integer): integer

    l2c_sx1262_spi_write_buffer: function(any, integer)

    -- [硬件中断与深渊挂起探针]
    l2c_setup_dio1_interrupt: function(integer)
    l2c_wait_for_radio: function()

    l2c_launch_core1: function(any)
    l2c_wake_main_core: function()
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

---------------------------------------------------------
-- 4. 射频参数配置与发射引擎 (0-GC 物理封装)
---------------------------------------------------------

-- 极速短包命令发送器
local function SX1262_send_cmd2(cmd: integer, arg1: integer)
    local buf = L2C_Buffer(2)
    -- 【核心修复：直接透传指针！干掉 L2C_PtrAsInt！】
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf), 0, cmd)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf), 1, arg1)
    
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
    C_ESP_IDF.l2c_sx1262_spi_write_buffer(L2C_Ref(buf), 2)
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
end

local function SX1262_send_cmd5(cmd: integer, a1: integer, a2: integer, a3: integer, a4: integer)
    local buf = L2C_Buffer(5)
    -- 【核心修复：直接透传指针！】
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf), 0, cmd)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf), 1, a1)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf), 2, a2)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf), 3, a3)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf), 4, a4)
    
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
    C_ESP_IDF.l2c_sx1262_spi_write_buffer(L2C_Ref(buf), 5)
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
end

-- 配置 CN470 与 Meshtastic LongFast 监听参数
local function SX1262_setup_meshtastic_sniffer()
    print("[SX1262] 切入 Meshtastic 窃听模式...")
    
    -- 1. 切换为 LoRa 模式
    SX1262_send_cmd2(0x8A, 0x01) 

    -- 2. [核心修复：切换到中国区 CN470 频段！]
    -- 首选尝试 470.375 MHz (0x1D 66 00 00)
    print("[SX1262] 锁定官方 CN 频道 470.375 MHz...")
    SX1262_send_cmd5(0x86, 0x1D, 0x66, 0x00, 0x00)
    
    -- (如果等下还是收不到，你可以注释掉上面那行，换成这行 470.000 MHz 试试)
    -- SX1262_send_cmd5(0x86, 0x1D, 0x60, 0x00, 0x00)

    -- 3. 设置基带参数 LongFast (SF11, BW 250kHz, CR 4/5)
    print("[SX1262] 锁定基带: SF11, BW250...")
    SX1262_send_cmd5(0x8B, 0x0B, 0x05, 0x01, 0x00)
    
    -- 4. 强行覆写网格同步字 (Sync Word = 0x2B44)
    print("[SX1262] 破解私有网格同步字...")
    local buf_sync = L2C_Buffer(5)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_sync), 0, 0x0D) 
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_sync), 1, 0x07) 
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_sync), 2, 0x40) 
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_sync), 3, 0x34) -- 修改这里为 0x14
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_sync), 4, 0x44) -- 修改这里为 0x24 
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
    C_ESP_IDF.l2c_sx1262_spi_write_buffer(L2C_Ref(buf_sync), 5)
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)

    -- 5. 配置接收报文结构 (Preamble 16, 显式报头, 最大长度 255)
    print("[SX1262] 初始化数据包捕获引擎...")
    local buf_pkt = L2C_Buffer(7)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pkt), 0, 0x8C)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pkt), 1, 0x00)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pkt), 2, 0x10) 
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pkt), 3, 0x00) 
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pkt), 4, 0xFF) 
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pkt), 5, 0x01) 
    C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pkt), 6, 0x00) 
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
    C_ESP_IDF.l2c_sx1262_spi_write_buffer(L2C_Ref(buf_pkt), 7)
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
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

-- 轮询 DIO1 中断并提取报文
local function SX1262_poll_rx()
    if C_ESP_IDF.gpio_get_level(EORA_BOARD.DIO1) == 1 then
        
        -- 1. 获取引发中断的真实原因 (0x12 GetIrqStatus)
        local tx_st = L2C_Buffer(4)
        local rx_st = L2C_Buffer(4)
        C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_st), 0, 0x12)
        C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_st), 1, 0x00) 
        C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_st), 2, 0x00) 
        C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_st), 3, 0x00) 
        
        C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
        C_ESP_IDF.l2c_sx1262_spi_transfer(L2C_Ref(tx_st), L2C_Ref(rx_st), 4)
        C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
        
        -- 提取 16位 的 IRQ 状态码
        local irq_high = C_ESP_IDF.l2c_get_byte(L2C_Ref(rx_st), 2)
        local irq_low  = C_ESP_IDF.l2c_get_byte(L2C_Ref(rx_st), 3)
        
        OLED_clear_3to6()
        OLED_print(3, ">> RADAR TRIGGERED!")
        OLED_print_num(4, "IRQ H: ", irq_high)
        OLED_print_num(5, "IRQ L: ", irq_low)
        print(" [L2C-RADAR] 拦截到电磁波！IRQ 状态 -> H: ", irq_high, " L: ", irq_low)
        
        -- 清除所有硬件中断标志位
        local buf_clr = L2C_Buffer(3)
        C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_clr), 0, 0x02)
        C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_clr), 1, 0x03)
        C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_clr), 2, 0xFF)
        C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
        C_ESP_IDF.l2c_sx1262_spi_write_buffer(L2C_Ref(buf_clr), 3)
        C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
        
        -- 【核心修复：强制重启连续接收模式，防止芯片掉线！】
        local buf_rx = L2C_Buffer(4)
        C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_rx), 0, 0x82)
        C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_rx), 1, 0xFF)
        C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_rx), 2, 0xFF)
        C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_rx), 3, 0xFF)
        C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
        C_ESP_IDF.l2c_sx1262_spi_write_buffer(L2C_Ref(buf_rx), 4)
        C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
        
    end
end

local function SX1262_init()
    print("[SX1262] 正在初始化 SPI 射频总线...")

    -- CS 片选引脚初始化为高电平
    C_ESP_IDF.gpio_set_direction(EORA_BOARD.CS, GPIO_MODE_OUTPUT)
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
    
    -- 触发底层的 C 语言 SPI 硬件初始化
    C_ESP_IDF.l2c_sx1262_spi_init(EORA_BOARD.SCK, EORA_BOARD.MISO, EORA_BOARD.MOSI)
    
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