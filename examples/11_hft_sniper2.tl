-- examples/11_hft_sniper2.tl (标准化重构版)
-- @l2c_import: std/zmq.tl

-- 1. 定义交易所推送的二进制内存对齐结构
local type TickPacket = record
    symbol_id: integer
    price: integer
    qty: integer
    _cast: function(any): TickPacket
end

local ma_window: {integer} = {0, 0, 0, 0, 0}
local window_idx = 1
local is_filled = false

local function on_tick_received(pkt: TickPacket)
    ma_window[window_idx] = pkt.price
    window_idx = window_idx + 1
    if window_idx > 5 then
        window_idx = 1
        is_filled = true
    end
    
    if is_filled == false then return end
    
    local sum = 0
    for i = 1, 5 do sum = sum + ma_window[i] end
    local ma_price = sum // 5
    
    if pkt.price > ma_price and pkt.qty > 100 then
        print(" [狙击开火] 捕捉到放量突破！Symbol:", pkt.symbol_id, "Price:", pkt.price, "MA:", ma_price)
    end
end

-- ==========================================
--  物理网关主程序
-- ==========================================
print(" L2C HFT Sniper 引擎启动，挂载 ZMQ 网卡...")

-- 极简封装：一行搞定环境和 Socket！
local ctx = ZMQ_Context()
local subscriber = ZMQ_Socket_Sub(ctx)
ZMQ_Connect(subscriber, "tcp://127.0.0.1:5555")

-- 极简封装：一键完成全市场行情订阅，告别恶心的 1 字节 Hack！
ZMQ_Subscribe_All(subscriber)

local msg_buf = L2C_Buffer(24)
print(" 雷达已锁定，等待二进制 Tick 数据轰炸...")

while true do
    -- 极简接收，直达物理内存
    local bytes = ZMQ_Recv(subscriber, L2C_Ref(msg_buf), 24)
    
    if bytes > 0 then
        local tick: TickPacket = TickPacket._cast(L2C_Ref(msg_buf))
        on_tick_received(tick)
    end
end