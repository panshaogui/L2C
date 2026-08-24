-- ==============================================================================
-- 压测 1：跨核双向 Ping-Pong 延迟 (真实物理总线穿透)
-- ==============================================================================
-- @l2c_import: std/multicore.tl
-- @l2c_import: std/ringbuffer.tl
-- @l2c_import: std/time.tl
-- @l2c_include: stdio.h

local type C_STDIO = record printf: function(string, integer): integer end

-- 1. 物理分配双向通道
-- 主核 -> 副核 队列
local function get_q_tx(): any return L2C_Static("SPSC_Queue") end
local function get_buf_tx(): integer return L2C_PtrAsInt(L2C_Static("[1024]integer")) end
-- 副核 -> 主核 队列
local function get_q_rx(): any return L2C_Static("SPSC_Queue") end
local function get_buf_rx(): integer return L2C_PtrAsInt(L2C_Static("[1024]integer")) end

local ITERATIONS = 1000000 -- 100 万回合！

-- ==========================================
-- 副核：极速反射镜
-- ==========================================
local function core1_reflector()
    local q_tx = get_q_tx()
    local q_rx = get_q_rx()
    local tmp_arr = L2C_IntegerArray(1)
    local ref = L2C_Ref(tmp_arr)
    
    while true do
        if SPSC_Pop(q_tx, ref) then
            local val = L2C_ReadArray(L2C_PtrAsInt(ref), 0)
            if val == -1 then break end -- 收到关闭信号
            
            -- 收到数据，立刻原样弹回！
            while not SPSC_Push(q_rx, val) do end
        end
    end
end

-- ==========================================
-- 主核：发球机与高精度秒表
-- ==========================================
-- 初始化双向隧道
SPSC_Init(get_q_tx(), 1024, get_buf_tx())
SPSC_Init(get_q_rx(), 1024, get_buf_rx())

print(" 启动跨核 Ping-Pong 延迟压测 (100万次回合)...")
Multicore_Launch(core1_reflector)

local q_tx = get_q_tx()
local q_rx = get_q_rx()
local tmp_arr = L2C_IntegerArray(1)
local ref = L2C_Ref(tmp_arr)

-- 预热缓存行 (Warmup)
for i = 1, 1000 do
    while not SPSC_Push(q_tx, 0) do end
    local popped = false
    while not popped do popped = SPSC_Pop(q_rx, ref) end
end

-- 掐表开始
local start_ns = time_now_ns()

for i = 1, ITERATIONS do
    while not SPSC_Push(q_tx, i) do end
    local popped = false
    while not popped do
        popped = SPSC_Pop(q_rx, ref)
    end
end

-- 掐表结束
local end_ns = time_now_ns()

-- 发送销毁信号
while not SPSC_Push(q_tx, -1) do end

local total_ns = end_ns - start_ns
local rtt_ns = total_ns // ITERATIONS
local one_way_ns = rtt_ns // 2

C_STDIO.printf(" 测试完成！总耗时: %lld 纳秒\n", total_ns)
C_STDIO.printf(" RTT (来回总延迟): %lld 纳秒\n", rtt_ns)
C_STDIO.printf(" 单向总线穿透延迟: %lld 纳秒\n", one_way_ns)