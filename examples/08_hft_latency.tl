-- examples/08_hft_latency.tl
-- @l2c_import: std/zmq.tl

-- 这里的 C 变量和 L2C_Buffer 都已经被物理拼接进来了，直接用！
local ctx = C_ZMQ.zmq_ctx_new()
local subscriber = C_ZMQ.zmq_socket(ctx, 2) -- ZMQ_SUB
local rc = C_ZMQ.zmq_connect(subscriber, "tcp://127.0.0.1:5555")

-- 🔥 物理开闸：ZMQ_SUBSCRIBE 宏的底层枚举值是 6。
-- 🔥 [物理降维]：C 语言需要 void* 指针，我们就在栈上强开 1 字节空内存当替身！
local empty_filter = L2C_Buffer(1)
C_ZMQ.zmq_setsockopt(subscriber, 6, L2C_Ref(empty_filter), 0)

print("🚀 M4 级裸机高速网关启动！(模块化 Unity Build 验证)")

local msg_buf = L2C_Buffer(1024)
while true do
    local bytes = C_ZMQ.zmq_recv(subscriber, L2C_Ref(msg_buf), 1024, 0)
    if bytes > 0 then
        print("🔥 截获狂暴数据，长度:", bytes)
    end
end
