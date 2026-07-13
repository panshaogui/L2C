-- examples/19_pico_blinky.tl
-- 物理合并底层驱动
-- @l2c_import: std/pico.tl
-- @l2c_import: std/freertos.tl

-- 这是一个纯正的硬实时任务，由 FreeRTOS 调度
local function led_task(_param: any)
    C_PICO.gpio_init(25)              -- Pico 板载 LED 对应的引脚是 25
    C_PICO.gpio_set_dir(25, PICO_GPIO_OUT) 
    
    while true do
        C_PICO.gpio_put(25, 1)        -- 灯亮
        freertos_delay_ms(500)        -- 硬件级休眠 500ms，交出 CPU 控制权
        C_PICO.gpio_put(25, 0)        -- 灯灭
        freertos_delay_ms(500)
    end
end

-- 初始化硬件串口打印功能
C_PICO.stdio_init_all()
print("🚀 L2C FreeRTOS 内核启动, 准备点亮边缘世界！")

-- 注册任务并启动操作系统的抢占式内核
-- 🔥 降维打击：在传参的瞬间，用 L2C_FuncPtr 把 Teal 局部函数强转为 C 物理指针！
freertos_create_task("BlinkyTask", L2C_FuncPtr(led_task))
C_FREERTOS.vTaskStartScheduler()
