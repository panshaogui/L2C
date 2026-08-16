-- ==============================================================================
-- examples/20_pico_multicore_blinky5.tl (多返回值 + C_STDIO 完美打印版)
-- ==============================================================================

-- @l2c_import: std/pico.tl
-- @l2c_import: std/multicore.tl
-- @l2c_import: std/ringbuffer.tl
-- @l2c_include: stdio.h

-- 引入 C 语言标准输入输出库，直接操控底层打印！
local type C_STDIO = record
    -- 注意：%lld 用于匹配底层 64 位的 integer
    printf: function(string, integer): integer
    puts: function(string): integer
end

local LED_PIN = 25  -- RP2040 Pico 板载绿灯 GP25

-- ============================================================================
-- 副核 (Core 1) 任务
-- ============================================================================
local function core1_hardware_task()
    C_PICO.gpio_init(LED_PIN)
    C_PICO.gpio_set_dir(LED_PIN, PICO_GPIO_OUT)
    
    L2C_Spinlock_Lock(0)
    C_STDIO.puts(" [Core 1 硬件层] 已安全苏醒，进入极速监听模式...")
    L2C_Spinlock_Unlock(0)
    
    while true do
        local ok, level = SPSC_PopDefault()
        
        if ok then
            C_PICO.gpio_put(LED_PIN, level)
            
            L2C_Spinlock_Lock(0)
            -- 核心修复：使用 printf，只有一个完整的字符串，彻底粉碎 \t 导致的退格错位！
            C_STDIO.printf(" [Core 1 执行] 收到信标！LED 状态翻转为: %lld\n", level)
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
C_STDIO.puts("==== L2C 双核无锁通讯阵列点火 (终极完美版) ====")
L2C_Spinlock_Unlock(0)

SPSC_InitDefault()
C_PICO.sleep_us(10000)

Multicore_Launch(core1_hardware_task)

L2C_Spinlock_Lock(0)
C_STDIO.puts(" [Core 0 心脏] Core 1 已启动，开始压入闪烁信标...")
L2C_Spinlock_Unlock(0)

local current_level = 0
while true do
    current_level = 1 - current_level
    
    while not SPSC_PushDefault(current_level) do
        C_PICO.sleep_us(2000)
    end
    
    L2C_Spinlock_Lock(0)
    -- 核心修复：使用 printf 格式化输出
    C_STDIO.printf(" [Core 0 发射] 已将电平信号压入通道 -> %lld\n", current_level)
    L2C_Spinlock_Unlock(0)
    
    C_PICO.sleep_us(500000)
end