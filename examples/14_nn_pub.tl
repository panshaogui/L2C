-- examples/14_nn_pub.tl
-- @l2c_import: std/nanomsg.tl
-- @l2c_include: unistd.h

local type C_LIBC = record
    sleep: function(integer): integer
end

local type MarketTick = record
    price: integer
    qty: integer
    _cast: function(any): MarketTick
end

-- 1. 建立 IPC 物理管道 (完全不走网卡网络层)
local pub = NN_Socket_Pub()
NN_Bind(pub, "ipc:///tmp/l2c_market.ipc")

print(" L2C 行情中枢启动，IPC 内存总线挂载完毕！")

-- 2. 极限优化：在栈上强开 16 字节物理内存，指针原地映射！
local buf = L2C_Buffer(16)
local pkt: MarketTick = MarketTick._cast(L2C_Ref(buf))

-- 初始状态
pkt.price = 60000
pkt.qty = 100

-- 3. 狂暴推送
while true do
    pkt.price = pkt.price + 1
    
    -- 直接把底层栈内存的地址丢给 nanomsg 发送，0 内存分配！
    NN_Send(pub, L2C_Ref(buf), 16)
    print(" [PUB] 内存总线广播 Tick:", pkt.price)
    
    C_LIBC.sleep(1)
end
