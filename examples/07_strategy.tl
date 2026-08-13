-- @l2c_import: std/zmq.tl
-- @l2c_import: std/cjson.tl

print(" L2C 高频网关启动 (ZMQ + 0-GC JSON解析)...")

local ctx = ZMQ_Context()
local subscriber = ZMQ_Socket_Sub(ctx)
ZMQ_Connect(subscriber, "tcp://127.0.0.1:5555")
ZMQ_Subscribe_All(subscriber)

local function on_tick()
    -- 在栈上开辟 1024 字节内存，用来接网卡数据
    local buf = L2C_Buffer(1024)
    local bytes = ZMQ_Recv(subscriber, L2C_Ref(buf), 1024)
    
    if bytes > 0 then
        -- 降维打击：直接把栈内存指针喂给 CJSON，全程无 Lua String 分配！
        local root = CJSON_ParseBuffer(L2C_Ref(buf))
        
        if root ~= nil then
            local price = CJSON_GetNumber(root, "price")
            print("Market Tick Price: ", price)
            CJSON_Free(root)
        end
    end
    
    -- O(1) 瞬时清空 Arena（以防其他业务在当前 Tick 产生了堆积）
    L2C_Tick_Reset()
end

while true do
    on_tick()
end