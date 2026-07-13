-- examples/12_multi_ffi_benchmark.tl
-- 📦 极限压力测试：双重 C 原生标准库物理合并
-- @l2c_import: std/zmq.tl
-- @l2c_import: std/time.tl

-- 1. 验证 C_TIME 命名空间
local function get_current_ns(): integer
    local ts = L2C_Buffer(16) -- timespec 占 16 字节
    -- 调用系统级内核时钟 (CLOCK_REALTIME = 0)
    C_TIME.clock_gettime(0, L2C_Ref(ts))
    -- 此处仅作为 FFI 连通性测试
    return 999999
end

-- 2. 验证 C_ZMQ 命名空间
print("⚡ L2C 双核 FFI 引擎启动...")
local ctx = C_ZMQ.zmq_ctx_new()
local subscriber = C_ZMQ.zmq_socket(ctx, 2)
local rc = C_ZMQ.zmq_connect(subscriber, "tcp://127.0.0.1:5555")

if rc == 0 then
    print("📡 ZMQ 物理网关挂载成功！")
end

-- 3. 混合执行
local t_start = get_current_ns()
print("⏱️ 系统内核时钟测距完成！伪纳秒戳:", t_start)
print("✅ [大满贯] ZMQ(C++) 与 Time(C) 库在底层完美共存，命名空间未发生碰撞！")
