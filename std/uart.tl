-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- std/uart.tl
-- L2C 0-GC 极速串口模块

-- @l2c_source: clib/mcu/l2c_uart.c

local type C_UART = record
    l2c_uart_init: function()
    l2c_uart_read_char: function(): integer
end

local function UART_init()
    C_UART.l2c_uart_init()
end

local function UART_read_char(): integer
    return C_UART.l2c_uart_read_char()
end