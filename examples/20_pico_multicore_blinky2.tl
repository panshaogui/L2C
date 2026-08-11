-- ==============================================================================
-- examples/20_pico_multicore_blinky2.tl (标准化重构版)
-- RP2040 双核物理交火测试：Core 0 (发射) -> SPSC -> Core 1 (消费+打印)
-- ==============================================================================

-- @l2c_import: std/pico.tl
-- @l2c_import: std/multicore.tl
-- @l2c_import: std/ringbuffer.tl

local LED_PIN = 25  -- RP2040 Pico 板载绿灯

-- ============================================================================
-- 🧠 副核 (Core 1) 任务
-- ============================================================================
local function core1_hardware_task()
    -- 依然使用您精妙的 0-GC 物理装箱
    local out = IntBox._new()
    
    C_PICO.gpio_init(LED_PIN)
    C_PICO.gpio_set_dir(LED_PIN, PICO_GPIO_OUT)
    print("🚀 [Core 1 硬件层] 已安全苏醒，进入极速监听模式...")
    
    while true do
        -- 💡 小白友好：直接调用 SPSC_GetDefaultQueue()，不再需要手写 L2C_Static
        if SPSC_Pop(SPSC_GetDefaultQueue(), out) then
            local level = out.val
            C_PICO.gpio_put(LED_PIN, level)
            print("  💡 [Core 1 执行] 收到信标！LED 状态翻转为: ", level)
        else
            C_PICO.sleep_us(1000)
        end
    end
end

-- ============================================================================
-- 🫀 主核 (Core 0) 任务
-- ============================================================================
C_PICO.stdio_init_all()
print("==== ⚡ L2C 双核无锁通讯阵列点火 (标准化极简版) ====")

-- 💡 小白友好：一行代码完成物理内存分配与队列初始化！
SPSC_InitDefault()

-- 确保 SRAM 写入完全透传
C_PICO.sleep_us(10000)

Multicore_Launch(L2C_FuncPtr(core1_hardware_task))
print("🫀 [Core 0 心脏] Core 1 已启动，开始压入闪烁信标...")

local current_level = 0
while true do
    current_level = 1 - current_level
    
    -- 💡 小白友好：直接推送
    while not SPSC_Push(SPSC_GetDefaultQueue(), current_level) do
        C_PICO.sleep_us(2000)
    end
    
    print("📡 [Core 0 发射] 已将电平信号压入队列 -> ", current_level)
    C_PICO.sleep_us(500000)
end
