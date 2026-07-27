-- ==============================================================================
-- examples/23_hft_matching_engine.tl
-- 华尔街极客级 HFT 撮合引擎 (Limit Order Book Matching Engine)
-- 核心技术：Bit-Packing 订单压缩、SPSC 无锁投递、0-GC 物理内存撮合
-- ==============================================================================

-- @l2c_import: std/multicore.tl
-- @l2c_import: std/ringbuffer.tl
-- @l2c_include: sched.h

local type C_LIBC = record
    sched_yield: function()
end

local type HFTState = record
    sum_matches: integer
    sum_volume: integer
    done: integer
    _cast: function(any): HFTState
end

local function Get_HFTState(): HFTState
    return HFTState._cast(L2C_Static("HFTState"))
end

-- 🔥 修复核心：强制单例模式，确保全局唯一的物理队列！
local function Get_SharedQueue(): SPSC_Queue
    return SPSC_Queue._cast(L2C_Static("SPSC_Queue"))
end

-- ============================================================================
-- 🧠 副核 (Core 1) 任务：限价订单簿 (LOB) 撮合核心
-- ============================================================================
local function matching_engine_task()
    local st = Get_HFTState()
    local q = Get_SharedQueue()
    local out = IntBox._new()
    
    -- 0-GC 物理分配：买单深度表和卖单深度表 (价格范围 0~10000)
    -- 由于是在纯静态的守护线程中，我们直接使用栈数组，享受最高级别的 L1 Cache 命中率！
    local bids = L2C_IntegerArray(10000)
    local asks = L2C_IntegerArray(10000)
    for i = 1, 10000 do bids[i] = 0; asks[i] = 0 end
    
    local best_bid = 0
    local best_ask = 10000
    
    local local_matches = 0
    local local_volume = 0
    
    print("🚀 [Core 1 撮合引擎] 启动完毕，限价订单簿 (LOB) 内存预热完成，等待订单流...")
    
    local draining = true
    while draining do
        if st.done == 1 and q.head == q.tail then
            draining = false
            break
        end

        if SPSC_Pop(q, out) then
            local packed = out.val
            -- ⚡ 极限解包 (Bit-Unpacking)：从一个 64 位整数中还原整个订单！
            -- [Side: 1位][Price: 16位][Qty: 16位][ID: 24位]
            local id = packed & 0xFFFFFF
            local qty = (packed >> 24) & 0xFFFF
            local price = (packed >> 40) & 0xFFFF
            local side = (packed >> 56) & 0x1
            
            if side == 0 then
                -- 🟢 买单 (Bid)：吃掉小于等于我出价的卖单
                while qty > 0 and best_ask <= price do
                    local ask_qty = asks[best_ask + 1]
                    if ask_qty > 0 then
                        local trade_qty = qty
                        if ask_qty < qty then trade_qty = ask_qty end
                        
                        asks[best_ask + 1] = ask_qty - trade_qty
                        qty = qty - trade_qty
                        local_volume = local_volume + trade_qty
                        local_matches = local_matches + 1
                    else
                        best_ask = best_ask + 1
                    end
                end
                -- 残余未成交的数量，挂入订单簿
                if qty > 0 then
                    bids[price + 1] = bids[price + 1] + qty
                    if price > best_bid then best_bid = price end
                end
                
            else
                -- 🔴 卖单 (Ask)：吃掉大于等于我出价的买单
                while qty > 0 and best_bid >= price do
                    local bid_qty = bids[best_bid + 1]
                    if bid_qty > 0 then
                        local trade_qty = qty
                        if bid_qty < qty then trade_qty = bid_qty end
                        
                        bids[best_bid + 1] = bid_qty - trade_qty
                        qty = qty - trade_qty
                        local_volume = local_volume + trade_qty
                        local_matches = local_matches + 1
                    else
                        best_bid = best_bid - 1
                    end
                end
                -- 残余未成交的数量，挂入订单簿
                if qty > 0 then
                    asks[price + 1] = asks[price + 1] + qty
                    if price < best_ask then best_ask = price end
                end
            end
        else
            C_LIBC.sched_yield() -- 队列空，让出 CPU
        end
    end
    
    st.sum_matches = local_matches
    st.sum_volume = local_volume
    L2C_Memory_Barrier()
end

-- ============================================================================
-- 🫀 主核 (Core 0) 任务：Feed Handler (高速订单发生器)
-- ============================================================================
print("==== 📈 L2C 纳秒级 HFT 撮合引擎 (Bit-Packing) ====")

local st = Get_HFTState()
local q = Get_SharedQueue()
st.sum_matches = 0
st.sum_volume = 0
st.done = 0

-- 初始化 1024 长度的无锁环形跑道
local buf_ptr = L2C_Static("[1024]integer")
SPSC_Init(q, 1024, L2C_PtrAsInt(buf_ptr))

-- 发射撮合核心！
Multicore_Launch(L2C_FuncPtr(matching_engine_task))

local TOTAL_ORDERS = 1000000
print("🫀 [Core 0 网络层] 开始向无锁队列疯狂倾泻 " , TOTAL_ORDERS , " 笔交易订单...")

for i = 1, TOTAL_ORDERS do
    -- 模拟网络流：随机买卖，价格集中在 100~110 之间，从而引发极其惨烈的物理撮合
    -- (在 L2C 0-GC 下，我们为了避开 math.random 库开销，手搓一个伪随机数)
    local pseudo_rand = (i * 1103515245 + 12345) & 0x7FFFFFFF
    
    local side = pseudo_rand & 1                  -- 0 或 1
    local price = 100 + ((pseudo_rand >> 1) % 11) -- 100 到 110
    local qty = 10                                -- 统一手数
    local id = i
    
    -- ⚡ 极限打包 (Bit-Packing)！将 4 个字段压成一个整型数字！
    local packed = (side << 56) | (price << 40) | (qty << 24) | id
    
    while not SPSC_Push(q, packed) do
        C_LIBC.sched_yield()
    end
end

L2C_Memory_Barrier()
st.done = 1

local wait_done = false
while not wait_done do
    L2C_Memory_Barrier()
    if st.sum_matches > 0 then wait_done = true end
    C_LIBC.sched_yield()
end

print("\n📊 ==== 撮合结算报告 (Match Report) ====")
print("🎯 吞吐的订单总数: ", TOTAL_ORDERS)
print("⚔️  发生的撮合次数: ", st.sum_matches)
print("💰 撮合的总成交量: ", st.sum_volume)