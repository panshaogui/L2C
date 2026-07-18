-- tests/11_static_memory.tl
-- 测试 L2C_Static 跨 Tick 持久化内存分配

local type OrderBook = record
    bids_vol: integer
    -- 🔥 L2C 铁律：声明零拷贝指针强转魔法
    _cast: function(any): OrderBook
end

-- 1. L2C_Static 负责在底层的 .bss 段开辟出干净的物理内存 (返回 any / void*)
-- 2. OrderBook._cast 负责在编译期告诉 Teal 和 Clang：“把这块内存当做 OrderBook 来用！”
local lob = OrderBook._cast(L2C_Static("OrderBook"))

local function on_tick()
    -- 现在 Teal 明确知道 lob 是 OrderBook，允许安全访问！
    lob.bids_vol = lob.bids_vol + 100
    print("当前累加成交量: ", lob.bids_vol)
    
    -- 瞬时重置临时竞技场内存
    L2C_Tick_Reset()
end

print("==== 跨 Tick 持久化状态测试 ====")
on_tick() -- 输出 100
on_tick() -- 输出 200
on_tick() -- 输出 300

-- EXPECT: ====跨Tick持久化状态测试====当前累加成交量:100当前累加成交量:200当前累加成交量:300