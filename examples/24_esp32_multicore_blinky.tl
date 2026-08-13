-- ==============================================================================
-- examples/24_esp32_multicore_blinky.tl
-- ESP32 双核物理交火测试：Core 0 (信标发生器) -> 无锁队列 -> Core 1 (GPIO 接管)
-- ==============================================================================

-- @l2c_import: std/multicore.tl
-- @l2c_import: std/ringbuffer.tl
-- @l2c_import: std/esp32.tl

local GPIO_NUM_2 = 2  -- ESP32 开发板自带的蓝色 LED 引脚

-- ============================================================================
-- 副核 (APP CPU - Core 1) 任务：物理引脚接管与队列消费
-- ============================================================================
local function core1_hardware_task()
    local q = Get_SharedQueue()
    local out = IntBox._new()
    
    -- 初始化物理引脚
    C_ESP32.gpio_reset_pin(GPIO_NUM_2)
    C_ESP32.gpio_set_direction(GPIO_NUM_2, ESP_GPIO_MODE_OUTPUT)
    
    print(" [Core 1 硬件层] 成功接管引脚 GPIO 2，进入极速监听模式...")
    
    while true do
        if SPSC_Pop(q, out) then
            local level = out.val
            C_ESP32.gpio_set_level(GPIO_NUM_2, level)
            print("  [Core 1 执行] 收到信标！LED 状态翻转为: ", level)
        else
            --【救命神药】队列为空时，调用 FreeRTOS 延时，让出 CPU 给看门狗！
            esp32_delay_ms(10)
        end
    end
end

-- ============================================================================
-- 主核 (PRO CPU - Core 0) 任务：心跳信标发生器
-- ============================================================================
print("==== L2C ESP32 双核无锁通讯阵列点火 ====")

local q = Get_SharedQueue()
local buf_ptr = L2C_Static("[1024]integer")
SPSC_Init(q, 1024, L2C_PtrAsInt(buf_ptr))

Multicore_Launch(core1_hardware_task)

print(" [Core 0 心脏] 开始以 500ms 为周期，向副核发射闪烁信标...")

local current_level = 0

while true do
    current_level = 1 - current_level
    
    while not SPSC_Push(q, current_level) do
        esp32_delay_ms(10)
    end
    print(" [Core 0 发射] 已将电平信号压入队列 -> ", current_level)
    
    -- 绝对休眠，完美调度
    esp32_delay_ms(500)
end