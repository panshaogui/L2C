-- examples/13_cjson_parser.tl
-- @l2c_import: std/cjson.tl

print("🚀 L2C 0-GC JSON 解析引擎启动...")

-- 模拟币安 WebSocket 推送的一条 JSON 字符串
local mock_binance_msg = '{"symbol": "BTCUSDT", "price": 64500.50, "qty": 1.5}'

-- 1. 物理层解析 (直接在 C 内存堆里构建 DOM 树，Lua 侧毫无 GC 感知)
local root = cjson_parse(mock_binance_msg)

if root ~= nil then
    -- 2. 极速提取数据
    local price = cjson_get_number(root, "price")
    local qty = cjson_get_number(root, "qty")
    
    print("✅ 解析成功！提取核心数据:")
    print("   -> 标的价格: ", price)
    print("   -> 挂单数量: ", qty)
    
    -- 3. 军规：C 内存必须手动物理销毁
    cjson_free(root)
else
    print("❌ JSON 解析失败，格式错误！")
end
