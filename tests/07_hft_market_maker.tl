-- tests/06_hft_market_maker.tl

-- 1. 定义盘口 Tick 结构
local type BookTick = record
    bid_px: integer
    bid_qty: integer
    ask_px: integer
    ask_qty: integer

    -- 声明构造函数，通过 Teal 的静态类型检查
    _new: function(integer, integer, integer, integer): BookTick
end

-- 2. 定义不平衡信号发生器
local type SignalGenerator = record
    last_imbalance: integer
    
    _new: function(): SignalGenerator
    calc_imbalance: function(SignalGenerator, BookTick): integer
end

function SignalGenerator:calc_imbalance(tick: BookTick): integer
    local total_qty = tick.bid_qty + tick.ask_qty
    if total_qty == 0 then return 0 end
    -- 使用 // 进行硬核整除，确保结果死死咬定在 integer 强类型上
    self.last_imbalance = ((tick.bid_qty - tick.ask_qty) * 100) // total_qty
    return self.last_imbalance
end

-- 3. 模拟实盘主循环
local function L2C_Tick_Reset() end

local function run_hft_loop(): integer
    local sig_gen = SignalGenerator._new()
    local fire_signals = 0
    
    -- 模拟 10 万次极速盘口不平衡瞬时冲击
    for i = 1, 100000 do
        -- 模拟 Tick 动态变化，交替产生多空信号
        local bid_q = 50 + (i % 50)
        local ask_q = 100 - (i % 50)
        
        -- 分配临时 Tick 内存对象（编译后会被劫持进入 Arena）
        local t = BookTick._new(10000, bid_q, 10050, ask_q)
        
        -- 计算信号
        local imbal = sig_gen:calc_imbalance(t)
        
        -- 滤波：如果买盘极度压倒卖盘（不平衡率 > 20%），触发多头狂暴信号
        if imbal > 20 then
            fire_signals = fire_signals + 1
        end
        
        -- O(1) 瞬时熔断清空本轮 Tick 分配的 BookTick 内存，永久 0 GC 绝不 OOM
        L2C_Tick_Reset()
    end
    
    return fire_signals
end

local total_fires = run_hft_loop()
print(total_fires)
-- EXPECT: 18000
