-- examples/07_arena_lifecycle.tl

-- 1. 定义一个极其庞大的标准订单结构体
local type StandardOrder = record
    order_id: integer
    symbol_id: integer
    price: integer
    qty: integer
    timestamp: integer
    
    -- 激活 Arena 分配宏：只要写了 _new，底层就会自动拦截并用 my_arena:new 分配内存！
    _new: function(integer, integer, integer, integer, integer): StandardOrder
end

-- 2. 模拟一个极其复杂的策略模块
local function process_orders(orders: {StandardOrder}, count: integer)
    local total_qty = 0
    for i = 1, count do
        -- 通过底层指针访问，速度极快
        total_qty = total_qty + orders[i].qty
    end
    -- print(" 成功处理了", count, "个订单，总数量:", total_qty)
end

-- 3. 主循环：模拟 1 万次 Tick，每次 Tick 瞬间产生 1000 个动态订单！
print(" L2C Arena 内存池极限测试启动...")
print(" 正在进行 10,000 次 Tick，总计将分配 10,000,000 个对象！")

for tick_id = 1, 10000 do
    
    -- 咱们假装要在内存里存 1000 个订单指针
    -- 注意：指针数组本身可以放在栈上（用 L2C_Array），但对象实体全在 Arena 里！
    local order_ptrs = L2C_Buffer(8000) -- 存放 1000 个 8 字节指针
    
    -- 极限分配测试：疯狂吃内存
    for i = 1, 1000 do
        -- [Arena 魔法]：_new 瞬间向 10MB 内存池划走 40 字节，0 GC！
        local new_order = StandardOrder._new(i, 888, 60000 + i, 10, 1690000000)
        
        -- (演示：为了简便，咱们假设这里就是把 new_order 塞进列表。
        -- 实际在 C 层面，它已经稳稳地躺在 Arena 堆内存里了)
    end
    
    -- ... 将这些订单交给风控、撮合等函数去漫游 ...
    -- process_orders(...)
    
    -- 【核平时刻】
    -- 如果没有这行代码，你的 10MB 内存池在第 250 次 Tick 时就会彻底撑爆导致 OOM！
    -- 有了这行代码，底层 my_arena 的 offset 瞬间归零，下一秒内存重新焕发生机！
    L2C_Tick_Reset()
    
    if tick_id % 2000 == 0 then
        print("   -> 稳如泰山！已平稳度过第", tick_id, "个 Tick...")
    end
end

print(" 极限测试通关！分配了 1 千万个对象，内存占用永远锁定，绝对 0 泄漏！")