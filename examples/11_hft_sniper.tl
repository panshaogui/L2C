-- examples/11_hft_sniper.tl
-- 📦 物理引入 L2C 标准库 (zmq 内部已经声明了 L2C_Buffer 和 L2C_Ref)
-- @l2c_import: std/zmq.tl

-- 1. 定义交易所推送的二进制内存对齐结构
local type TickPacket = record
    symbol_id: integer
    price: integer
    qty: integer
    -- 🔥 开启零拷贝强转特权
    _cast: function(any): TickPacket
end

-- 2. 策略状态：在 C 栈上开辟一块 5 周期的极速滑动窗口，0 GC！
local ma_window: {integer} = {0, 0, 0, 0, 0}
local window_idx = 1
local is_filled = false

-- 3. 核心策略：微型均线突破刺客
local function on_tick_received(pkt: TickPacket)
    -- 更新滑动窗口 (完美映射底层 0-based C 数组)
    ma_window[window_idx] = pkt.price
    window_idx = window_idx + 1
    if window_idx > 5 then
        window_idx = 1
        is_filled = true
    end
    
    if is_filled == false then return end
    
    -- 极限 For 循环计算均线
    local sum = 0
    for i = 1, 5 do
        sum = sum + ma_window[i]
    end
    -- ⚡ 使用整数除法 // ，压榨 CPU 时钟周期
    local ma_price = sum // 5
    
    -- 核心狙击逻辑：价格瞬间突破均线，且带量！
    if pkt.price > ma_price then
        if pkt.qty > 100 then
            print("🔫 [狙击开火] 捕捉到放量突破！Symbol:", pkt.symbol_id, "Price:", pkt.price, "MA:", ma_price)
        end
    end
end

-- ==========================================
-- 🚀 物理网关主程序
-- ==========================================
print("⚡ L2C HFT Sniper 引擎启动，挂载 ZMQ 网卡...")
local ctx = C_ZMQ.zmq_ctx_new()
local subscriber = C_ZMQ.zmq_socket(ctx, 2) -- ZMQ_SUB
C_ZMQ.zmq_connect(subscriber, "tcp://127.0.0.1:5555")

local msg_buf = L2C_Buffer(24)

print("📡 雷达已锁定，等待二进制 Tick 数据轰炸...")

while true do
    local bytes = C_ZMQ.zmq_recv(subscriber, L2C_Ref(msg_buf), 24, 0)
    if bytes > 0 then
        -- 🔥 零拷贝降维打击：字节流原地变身为 TickPacket 结构体！
        local tick: TickPacket = TickPacket._cast(L2C_Ref(msg_buf))
        on_tick_received(tick)
    end
end