-- tests/fail_06_vararg_pack.tl
-- EXPECT_FAIL: E001

local function log_data(...: any)
    print("试图将变长参数隐式打包为堆内存表...")
    
    -- 变长参数如果没有静态强类型约束，禁止直接打包
    -- 我们的 literal_table 语义安检站会将其当场击毙！
    local args = {...}
    print(args[1])
end

log_data(10, 20, 30)