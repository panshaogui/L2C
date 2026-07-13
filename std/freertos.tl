-- ==============================================================================
-- Copyright (c) 2026 L2C Architect | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- std/freertos.tl
-- @l2c_include: FreeRTOS.h
-- @l2c_include: task.h

local type C_FREERTOS = record
    xTaskCreate: function(any, string, integer, any, integer, any): integer
    vTaskDelay: function(integer)
    vTaskStartScheduler: function()
end

-- 高层优雅封装，扁平化命名防止冲突
local function freertos_create_task(name: string, func_ptr: any)
    -- 🔥 核心降维打击：利用 L2C_FuncPtr 把 Teal 局部函数强转为 C 物理指针！
    C_FREERTOS.xTaskCreate(func_ptr, name, 256, nil, 1, nil)
end

local function freertos_delay_ms(ms: integer)
    C_FREERTOS.vTaskDelay(ms) 
end

local function freertos_start()
    C_FREERTOS.vTaskStartScheduler()
end
