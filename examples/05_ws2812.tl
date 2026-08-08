-- ==============================================
-- 05_ws2812.tl: L2C PIO HLS 点亮幻彩灯带 (Wokwi 靶场版)
-- ==============================================

-- @l2c_import: std/pico.tl
-- @l2c_include: clib/ws2812_helpers.h

-- 1. 思想域：降维级 WS2812 时序逻辑 (完美 11-Cycle 架构)
local function L2C_PIO_ws2812()
    -- 确保状态机启动时，接管引脚为输出模式
    set("pindirs", 1)

    ::bitloop::
    -- 🌟【核心修复】: 先取数据！如果没数据，PIO 会在这里挂起休眠。
    -- 因为此时处于循环的起点，引脚必然维持在上一周期的 LOW 状态，完美形成 50us RESET 信号！
    out("x", 1)

    -- 取到数据后，发送周期正式开始，拉高并消耗 2 个周期
    set("pins", "1 [1]")
    -- 判断跳转 (消耗 1 周期) -> 至此，无论如何电平都维持了 3 个周期的 HIGH (375ns)
    jmp("!x", "do_zero")

    ::do_one::
    -- 发送 1：继续保持 HIGH 4 周期 (总计 7 周期 = 875ns，完美符合 T1H)
    set("pins", "1 [3]")
    -- 拉低 LOW 2 周期 (250ns)
    set("pins", "0 [1]")
    -- 跳回循环，消耗 1 周期 LOW，加上 out 消耗的 1 周期 LOW，总 LOW 500ns 完美！
    jmp("bitloop")

    ::do_zero::
    -- 发送 0：立即拉低 LOW 4 周期 
    set("pins", "0 [3]")
    -- 继续拉低 LOW 2 周期 (加上跳回，总计 8 周期 = 1000ns，完美符合 T0L)
    set("pins", "0 [1]")
    jmp("bitloop")

end

local type C_WS2812 = record
    c_pio_ws2812_init: function(integer)
    c_pio_ws2812_put: function(integer, integer, integer)
end

-- ===============================================
-- 2. 物理执行域 (主循环)
-- ===============================================
C_PICO.stdio_init_all()

local PIN_DIN = 15 
C_WS2812.c_pio_ws2812_init(PIN_DIN)

print("🌈 L2C WS2812 幻彩驱动已启动！")

local offset = 0
while true do
    for i = 0, 7 do
        local r = 0
        local g = 0
        local b = 0
        
        -- 流星拖尾算法
        if i == offset then
            r = 255 -- 领头红
        elseif i == ((offset + 1) % 8) then
            g = 255 -- 拖尾绿
        elseif i == ((offset + 2) % 8) then
            b = 255 -- 拖尾蓝
        else
            -- 极其微弱的白光，证明芯片活着
            r = 2
            g = 2
            b = 2
        end
        
        C_WS2812.c_pio_ws2812_put(r, g, b)
    end

    offset = (offset + 1) % 8
    C_PICO.sleep_us(100000) -- 每 100ms 刷新一帧
end