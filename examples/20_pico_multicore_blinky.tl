-- ==============================================================================
-- examples/20_pico_multicore_blinky.tl
-- RP2040 双核物理交火测试：Core 0 (发射) -> SPSC -> Core 1 (消费+打印)
-- ==============================================================================

-- @l2c_import: std/pico.tl
-- @l2c_import: std/multicore.tl
-- @l2c_import: std/ringbuffer.tl

local LED_PIN = 25  -- RP2040 Pico 板载绿灯 GP25

-- ============================================================================
-- 副核 (Core 1) 任务：物理引脚接管、队列消费 与 安全打印
-- ============================================================================
local function core1_hardware_task()
    local q = Get_SharedQueue()
    local out = IntBox._new()
    
    -- 初始化物理引脚 GP25
    C_PICO.gpio_init(LED_PIN)
    C_PICO.gpio_set_dir(LED_PIN, PICO_GPIO_OUT)
    
    -- 锁机制开启后，Core 1 启动日志也可以畅快打印了！
    print(" [Core 1 硬件层] 已安全苏醒，Spinlock 守护中，进入极速监听模式...")
    
    while true do
        if SPSC_Pop(q, out) then
            local level = out.val
            C_PICO.gpio_put(LED_PIN, level)
            
            --【受 Spinlock 保护】双核同时 print 再也不会触发物理 HardFault 或卡死！
            print("  [Core 1 执行] 收到信标！LED 状态翻转为: ", level)
        else
            -- 队列为空时休眠 1ms，释放 SRAM 总线带宽
            C_PICO.sleep_us(1000)
        end
    end
end

-- ============================================================================
--  主核 (Core 0) 任务：硬件初始化与心跳信标发生器
-- ============================================================================

-- 1.【Pico 裸机第一步】点火初始化 SDK 标准库 (UART / 时钟)
C_PICO.stdio_init_all()

print("==== L2C RP2040 双核无锁通讯阵列点火 (Spinlock 保护版) ====")

-- 2. 初始化静态 SPSC 队列
local q = Get_SharedQueue()
local buf_ptr = L2C_Static("[1024]integer")
SPSC_Init(q, 1024, L2C_PtrAsInt(buf_ptr))

-- 确保 SRAM 写入完全透传
C_PICO.sleep_us(10000)

-- 3. 点火 Core 1
Multicore_Launch(core1_hardware_task)

print(" [Core 0 心脏] Core 1 已启动，开始以 500ms 周期压入闪烁信标...")

local current_level = 0

while true do
    current_level = 1 - current_level
    
    -- 将信号压入 SPSC 队列
    while not SPSC_Push(q, current_level) do
        C_PICO.sleep_us(2000)
    end
    
    print(" [Core 0 发射] 已将电平信号压入队列 -> ", current_level)
    
    -- 周期休眠 500ms
    C_PICO.sleep_us(500000)
end