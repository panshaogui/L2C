-- examples/18_simdjson_test.tl
-- @l2c_import: std/simdjson.tl

print("🚀 L2C AVX-512/SSE4.2 极限 JSON 解析引擎启动...")

local json_payload = '{"symbol": "ETHUSDT", "price": 3150.88, "volume": 142.5}'
local len = #json_payload -- 让编译器自己算（算出来是 57）

print("📊 自动探测字符串长度: ", len)

-- 1. 调用 C++ 胶水层光速解析
local root = simd_parse(json_payload, len)

if root ~= nil then
    -- 2. 提取数据
    local price = simd_get_number(root, "price")
    local vol = simd_get_number(root, "volume")
    
    print("✅ C++ 底层解析成功！提取数据:")
    print("   -> 标的价格: ", price)
    print("   -> 交易量:   ", vol)
    
    -- 3. 释放 C++ 对象
    simd_free(root)
else
    print("❌ JSON 解析失败！")
end
