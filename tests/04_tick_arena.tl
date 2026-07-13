-- tests/04_tick_arena.tl
local type Order = record
    price: integer
    qty: integer
    
    -- 🔥 告诉 Teal：Order 身上确实有一个叫 _new 的类方法
    -- 它接收两个 integer，返回一个完整的 Order 对象
    _new: function(integer, integer): Order
end

-- 模拟高频交易的 Tick 驱动
local function on_tick(p: integer): integer
    -- 现在 Teal 认账了，它知道这会返回一个完美的 Order 强类型
    local o: Order = Order._new(p, 10)
    return o.price * o.qty
end

local total_volume = 0
-- 模拟 10 万次极速 Tick 推送
for i = 1, 100000 do
    total_volume = on_tick(i)
end

print(total_volume)
-- EXPECT: 1000000
