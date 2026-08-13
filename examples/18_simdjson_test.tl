-- examples/18_simdjson_test.tl
-- @l2c_import: std/simdjson.tl

print(" L2C AVX-512/SSE4.2 极限 JSON 解析引擎启动...")

local json_payload = '{"symbol": "ETHUSDT", "price": 3150.88, "volume": 142.5}'
-- 极其舒适：直接扔进字符串，无需手动传长度！

local root = SIMDJSON_Parse(json_payload)
if root ~= nil then
    local price = SIMDJSON_GetNumber(root, "price")
    local vol = SIMDJSON_GetNumber(root, "volume")
    print(" C++ 底层解析成功！提取数据:")
    print("   -> 标的价格: ", price)
    print("   -> 交易量:   ", vol)
    SIMDJSON_Free(root)
else
    print(" JSON 解析失败！")
end