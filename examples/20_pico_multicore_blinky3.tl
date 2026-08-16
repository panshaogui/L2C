-- ==============================================================================
-- examples/20_pico_multicore_blinky3.tl (多返回值解包终极版)
-- ==============================================================================

-- @l2c_import: std/pico.tl
-- @l2c_import: std/multicore.tl
-- @l2c_import: std/ringbuffer.tl

local LED_PIN = 25  -- 如果是 Pico W 请外接引脚，老款为 25

-- ============================================================================
-- 副核 (Core 1) 任务
-- ============================================================================

local function core1_hardware_task()
    C_PICO.gpio_init(LED_PIN)
    C_PICO.gpio_set_dir(LED_PIN, PICO_GPIO_OUT)
    print(" [Core 1 硬件层] 已安全苏醒，进入极速监听模式...")
    
    while true do
        -- 终极优雅：像原生 Lua 一样接收多返回值！再也看不到任何指针和对象！
        local ok, level = SPSC_PopDefault()
        
        if ok then
            C_PICO.gpio_put(LED_PIN, level)
            print(" [Core 1 执行] 收到信标！LED 状态翻转为: ", level)
        else
            C_PICO.sleep_us(1000)
        end
    end
end

-- ============================================================================
-- 主核 (Core 0) 任务
-- ============================================================================

C_PICO.stdio_init_all()
print("==== L2C 双核无锁通讯阵列点火 (终极语法糖版) ====")

-- 极简初始化
SPSC_InitDefault()
C_PICO.sleep_us(10000)

Multicore_Launch(core1_hardware_task)
print(" [Core 0 心脏] Core 1 已启动，开始压入闪烁信标...")

local current_level = 0
while true do
    current_level = 1 - current_level
    
    -- 极简推送
    while not SPSC_PushDefault(current_level) do
        C_PICO.sleep_us(2000)
    end
    
    print(" [Core 0 发射] 已将电平信号压入通道 -> ", current_level)
    C_PICO.sleep_us(500000)
end