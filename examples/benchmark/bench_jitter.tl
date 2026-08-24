-- ==============================================================================
-- 压测 2：0-GC 内存池抖动捕捉 (P99 Jitter)
-- ==============================================================================
-- @l2c_import: std/time.tl
-- @l2c_include: stdio.h

local type C_STDIO = record 
    printf: function(string, integer): integer 
    puts: function(string): integer 
end

local type MockOrder = record
    price: integer
    qty: integer
    _new: function(): MockOrder
end

print(" 启动 0-GC Tick Arena 极限抗抖动压测 (100万次对象分配)...")

local ITERATIONS = 1000000

local max_latency_ns = 0
local sum_latency_ns = 0

-- 为了防止 OS 线程调度的巨大干扰，我们先预热系统时钟
local _ = time_now_ns()

for i = 1, ITERATIONS do
    -- 记录操作前时间戳
    local t1 = time_now_ns()
    
    -- 疯狂分配内存对象！这在带 GC 的语言里是自杀行为！
    local order = MockOrder._new()
    order.price = 60000 + i
    order.qty = 100
    
    -- O(1) 瞬时清空，拒绝 GC 扫描！
    L2C_Tick_Reset()
    
    -- 记录操作后时间戳
    local t2 = time_now_ns()
    
    local latency = t2 - t1
    sum_latency_ns = sum_latency_ns + latency
    
    -- 捕捉最大毛刺 (Max Jitter)
    if latency > max_latency_ns then
        max_latency_ns = latency
    end
end

local avg_ns = sum_latency_ns // ITERATIONS

C_STDIO.puts(" 100万次内存分配完成！\n")
C_STDIO.printf(" 平均单次分配与清空耗时: %lld 纳秒\n", avg_ns)
C_STDIO.printf(" 捕捉到的最大毛刺 (Max Jitter): %lld 纳秒\n", max_latency_ns)