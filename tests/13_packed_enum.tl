-- tests/13_packed_enum.tl

print(" L2C 紧凑内存与强类型枚举 (Packed & Enum) 物理测试启动...")

-- 特性 1：Teal 原生 Enum！底层会变成 C 的 0, 1, 2
local type TradeState = enum
    "STATE_IDLE"
    "STATE_BUY"
    "STATE_SELL"
end

-- 特性 2：声明网络原生报文，L2C 嗅探到 Packed_，将在 C 语言里强制消除所有内存空隙！
local type Packed_TickMsg = record
    state: TradeState  -- 占用 4 字节或 8 字节
    price: integer     -- 占用 8 字节
    _cast: function(any): Packed_TickMsg
end

local function process_tick(pkt: Packed_TickMsg)
    -- 利用 Teal 强大的类型推断，状态机再也不用写魔术数字 0 或 1 了！
    if pkt.state == "STATE_BUY" then
        print(" 触发买入状态！价格: ", pkt.price)
    elseif pkt.state == "STATE_SELL" then
        print(" 触发卖出状态！价格: ", pkt.price)
    else
        print(" 闲置状态，不操作。")
    end
end

-- 物理执行域
local buf = L2C_Buffer(16)
local pkt: Packed_TickMsg = Packed_TickMsg._cast(L2C_Ref(buf))

-- 模拟网卡灌入的数据
pkt.state = "STATE_BUY"
pkt.price = 64500

process_tick(pkt)

-- EXPECT: L2C紧凑内存与强类型枚举(Packed&Enum)物理测试启动...触发买入状态！价格:64500