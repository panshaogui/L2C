-- ==============================================================================
-- examples/24_pico_multicore_blinky4.tl (多核保护装甲版)
-- ==============================================================================

-- @l2c_import: std/pico.tl
-- @l2c_import: std/multicore.tl
-- @l2c_import: std/ringbuffer.tl

local LED_PIN = 25

-- ============================================================================
-- 副核 (Core 1) 任务
-- ============================================================================
local function core1_hardware_task()
    C_PICO.gpio_init(LED_PIN)
    C_PICO.gpio_set_dir(LED_PIN, PICO_GPIO_OUT)
    
    L2C_Spinlock_Lock(0)
    print(" [Core 1 硬件层] 已安全苏醒，进入极速监听模式...")
    L2C_Spinlock_Unlock(0)
    
    while true do
        local ok, level = SPSC_PopDefault()
        
        if ok then
            C_PICO.gpio_put(LED_PIN, level)
            
            -- 硬件锁存器保护，独占串口总线！
            L2C_Spinlock_Lock(0)
            print(" [Core 1 执行] 收到信标！LED 状态翻转为: ", level)
            L2C_Spinlock_Unlock(0)
        else
            C_PICO.sleep_us(1000)
        end
    end
end

-- ============================================================================
-- 主核 (Core 0) 任务
-- ============================================================================
C_PICO.stdio_init_all()

L2C_Spinlock_Lock(0)
print("==== L2C 双核无锁通讯阵列点火 (硬件锁保护版) ====")
L2C_Spinlock_Unlock(0)

SPSC_InitDefault()
C_PICO.sleep_us(10000)

Multicore_Launch(core1_hardware_task)

L2C_Spinlock_Lock(0)
print(" [Core 0 心脏] Core 1 已启动，开始压入闪烁信标...")
L2C_Spinlock_Unlock(0)

local current_level = 0
while true do
    current_level = 1 - current_level
    
    while not SPSC_PushDefault(current_level) do
        C_PICO.sleep_us(2000)
    end
    
    -- 硬件锁存器保护，独占串口总线！
    L2C_Spinlock_Lock(0)
    print(" [Core 0 发射] 已将电平信号压入通道 -> ", current_level)
    L2C_Spinlock_Unlock(0)
    
    C_PICO.sleep_us(500000)
end