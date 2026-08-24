-- @l2c_import: std/ringbuffer.tl
-- @l2c_import: std/time.tl

print(" L2C SPSC 无锁队列吞吐量极限压测开始...")

SPSC_InitDefault()
local ITERATIONS = 10000000 -- 1000 万次 Push/Pop

-- 获取绝对单调时钟 (纳秒)
local start_ns = time_now_ns()

for i = 1, ITERATIONS do
    -- 强行塞入，模拟极限压榨
    while not SPSC_PushDefault(i) do end
    local ok, val = SPSC_PopDefault()
end

local end_ns = time_now_ns()
local elapsed_sec = (end_ns - start_ns) / 1000000000.0

print(" 测试完成！")
print("总耗时: ", elapsed_sec, " 秒")
print("吞吐量: ", ITERATIONS / elapsed_sec, " Ops/sec")