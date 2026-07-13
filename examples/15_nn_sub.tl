-- examples/15_nn_sub.tl
-- @l2c_import: std/nanomsg.tl

local type MarketTick = record
    price: integer
    qty: integer
    _cast: function(any): MarketTick
end

-- 1. 挂载到同一条 IPC 管道
local sub = C_NN.nn_socket(NN_AF_SP, NN_SUB)
local endpoint = "ipc:///tmp/l2c_market.ipc"
C_NN.nn_connect(sub, endpoint)

-- 2. 开闸放水：订阅全部消息
local empty_filter = L2C_Buffer(1)
C_NN.nn_setsockopt(sub, NN_SUB, NN_SUB_SUBSCRIBE, L2C_Ref(empty_filter), 0)

print("🚀 L2C 高频刺客待命，死死监听 IPC 共享内存...")

-- 3. C 栈上开辟 16 字节接货缓冲
local buf = L2C_Buffer(16)

while true do
    -- ⚠️ 极限物理操作：接收数据 -> 直接怼进栈内存
    local bytes = C_NN.nn_recv(sub, L2C_Ref(buf), 16, 0)
    
    if bytes == 16 then
        -- 🔥 零拷贝降维打击：字节流原地变身，无需反序列化！
        local pkt: MarketTick = MarketTick._cast(L2C_Ref(buf))
        print("🎯 [IPC 零拷贝命中] 价格:", pkt.price, " 挂单量:", pkt.qty)
    end
end
