require "std.pico"
-- @l2c_source: clib/la_helpers.h
-- @l2c_include: pico/stdio.h

-- ==============================================
-- Pico 协处理器: PIO 慢速时钟发生器与总线截获
-- ==============================================

local function L2C_PIO_la_reader()
    -- 拉高 read_clk
    set("pins", 1)
    
    -- 等待 FPGA 响应并在杜邦线上稳定电平
    set("x", 10)
    ::delay_h::
    jmp("x--", "delay_h")
    
    -- 吸入 8 位数据入 FIFO
    in_("pins", 8)
    
    -- 拉低 read_clk
    set("pins", 0)
    set("x", 10)
    ::delay_l::
    jmp("x--", "delay_l")
end

-- ==============================================
-- 主 CPU (Core 0): 战术调度与回传
-- ==============================================
local type C_LA = record
    c_pio_la_init: function(integer, integer)
    c_pio_la_read_fifo: function(): integer
end

local type C_STDIO = record
    putchar_raw: function(integer)
end

C_PICO.stdio_init_all()

local pin_base = 2  -- GPIO 2-9 接入 FPGA 的数据输出
local pin_clk = 10  -- GPIO 10 接入 FPGA 的读时钟输入 (read_clk)
C_LA.c_pio_la_init(pin_base, pin_clk)

print(" L2C Logic Analyzer Armed and Ready!")

while true do
    C_PICO.sleep_us(2000000)
    print(">>> Triggering Memory Dump from FPGA...")
    
    -- 抽干 127 字节并砸给 USB CDC
    for i = 0, 127 do
        local byte_val = C_LA.c_pio_la_read_fifo()
        C_STDIO.putchar_raw(byte_val)
    end
    
    print("<<< Dump Complete.")
end