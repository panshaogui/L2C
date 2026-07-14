-- @l2c_import: std/zmq.tl
-- @l2c_import: std/cjson.tl

-- Initialize ZMQ Subscriber
local ctx = C_ZMQ.zmq_ctx_new()
local subscriber = C_ZMQ.zmq_socket(ctx, 2)
C_ZMQ.zmq_connect(subscriber, "tcp://127.0.0.1:5555")

local function on_tick()
    local buf = L2C_Buffer(1024)
    local bytes = C_ZMQ.zmq_recv(subscriber, L2C_Ref(buf), 1024, 0)
    
    if bytes > 0 then
        -- 0-GC DOM parsing on C-Heap
        local root = cjson_parse(L2C_Cast(L2C_Ref(buf), "cstring"))
        local price = cjson_get_number(root, "price")
        print("Market Tick Price: ", price)
        cjson_free(root)
    end
    
    -- O(1) Memory Pool Reset to prevent OOM
    L2C_Tick_Reset()
end
