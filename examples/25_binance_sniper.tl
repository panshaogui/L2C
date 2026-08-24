-- ==============================================================================
-- 21_binance_sniper.tl: L2C 真实物理世界网络测距与解析
-- ==============================================================================
-- @l2c_import: std/http.tl
-- @l2c_import: std/cjson.tl

print(" L2C 高频网关启动，直连 Binance 核心机房...")

local json_buf = L2C_Buffer(10240)

local url = "https://api.binance.com/api/v3/ticker/price?symbol=BTCUSDT"
print(" 正在传输，获取 BTCUSDT 实时价格...")

local bytes = HTTP_Get(url, L2C_Ref(json_buf), 10240)

if bytes > 0 then
    print(" 数据灌入成功，总计物理字节数: ", bytes)
    
    -- 暴力输出：把栈内存强转为 C 字符串打印出来！
    local raw_json = L2C_Cast(L2C_Ref(json_buf), "cstring")
    print("   [截获生肉]: ", raw_json)
    
    local root = CJSON_ParseBuffer(L2C_Ref(json_buf))
    if root ~= nil then
        -- 核心狙击：使用新加的字符串剥离器！
        local price_str = CJSON_GetString(root, "price")
        print("   提取到最新 BTCUSDT 价格:  USDT ", price_str)
        
        CJSON_Free(root)
    else
        print(" JSON 解析失败，格式错误！")
    end
else
    print(" 网络通信中断或内存溢出！")
end