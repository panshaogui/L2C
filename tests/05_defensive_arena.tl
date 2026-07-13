-- tests/05_defensive_arena.tl
local type Order = record
    price: integer
    qty: integer
    is_buy: boolean
    -- 故意告诉 Teal 构造函数只接收 1 个参数，骗过上层静态检查
    _new: function(integer): Order 
end

-- 高层打个桩，骗过 Teal 的语法检查，底层会被劫持
local function L2C_Tick_Reset() end

local function test_tick(): integer
    -- 我们只传了 price，没有传 qty 和 is_buy！
    local o: Order = Order._new(99) 
    
    local default_qty = o.qty  -- 底层应该被自动兜底初始化为 0
    
    -- O(1) 瞬时清空竞技场内存，防止 OOM
    L2C_Tick_Reset()
    
    return default_qty
end

local res = test_tick()
print(res)

-- EXPECT: 0
