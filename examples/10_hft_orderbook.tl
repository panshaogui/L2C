-- ==============================================
-- 10_hft_orderbook.tl: L2C HFT 绝对连续订单簿内存阵列
-- ==============================================

local type Order = record
    price: integer
    qty: integer
    -- 魔法签证：向 Teal 发誓，我会返回一个强类型的 Order 数组！
    _cast_arr: function(any): {Order}
end

print(" L2C 高频交易 0-GC 连续订单簿内存阵列启动...")

-- 1. 划拨物理内存
local ob_ptr = L2C_RecordArray("Order", 1000)

-- 2. 完美强转：
-- Teal 看到 _cast_arr，放行了 {Order} 类型的赋值。
-- Nelua 看到 _cast_arr，被编译器偷偷替换成了 (@*[0]Order)(ob_ptr)，完美支持 ob[i] 索引！
local ob = Order._cast_arr(ob_ptr)

print(" 物理内存划拨完毕！开始写入订单并测试缓存行性能...")

-- 疯狂写入 (由于是连续内存，CPU 预取器 prefetcher 会将它们瞬间塞满 L1 Cache！)
for i = 1, 1000 do
    ob[i].price = 60000 + i
    ob[i].qty = i * 10
end

print(" 写入完成！抽查订单状态:")
print("   -> 订单#1: Price =", ob[1].price, " Qty =", ob[1].qty)
print("   -> 订单#500: Price =", ob[500].price, " Qty =", ob[500].qty)
print("   -> 订单#1000: Price =", ob[1000].price, " Qty =", ob[1000].qty)

-- 主循环清空，0 耗时
L2C_Tick_Reset()