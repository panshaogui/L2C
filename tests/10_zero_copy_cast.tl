-- tests/10_zero_copy_cast.tl
local type TradePacket = record
    price: integer
    qty: integer
    -- 🔥 优雅声明强转魔法，完美满足 Teal 的强类型洁癖！
    _cast: function(any): TradePacket
end

-- 申明高频内存魔法宏
local function L2C_Buffer(size: integer): any end
local function L2C_Ref(var: any): any end

local function test_zero_copy(): integer
    -- 1. 模拟网卡收到 16 字节的连续物理栈内存
    local msg_buf = L2C_Buffer(16)
    
    -- 2. ⚡ 零拷贝内存映射！直接在类型实体上调用 _cast 挂载物理指针
    local pkt: TradePacket = TradePacket._cast(L2C_Ref(msg_buf))
    
    -- 3. 此时操作 pkt，就是在 0 延迟地读写 msg_buf 的原生内存！
    pkt.price = 45000
    pkt.qty = 2
    
    return pkt.price * pkt.qty
end

local result = test_zero_copy()
print(result)

-- EXPECT: 90000
