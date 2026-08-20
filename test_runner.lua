-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- test_runner.lua：L2C 自动化单元测试框架
package.path = package.path .. ";./?.lua;"

--  [全新插队]：引入并运行单模块白盒测试器
local unit_runner = require("tests.unit.unit_runner")
local unit_ok = unit_runner.run()

if not unit_ok then
    print("\n [熔断] 单模块白盒测试有挂科，终止实弹演习！请先修复局部 Bug。")
    os.exit(1)
end

local function get_files(dir)
    local p = io.popen('find "'..dir..'" -type f -name "*.tl"')
    local files = {}
    for file in p:lines() do table.insert(files, file) end
    return files
end

local function run_tests()
    local test_files = get_files("tests")
    table.sort(test_files)
    
    local passed, failed = 0, 0
    print("========================================")
    print(" 启动 L2C 单元测试套件...")
    print("========================================")

    for _, file in ipairs(test_files) do
        -- 读取 EXPECT 和 EXPECT_FAIL 注释
        local expect_val = nil
        local expect_fail_val = nil
        for line in io.lines(file) do
            local match_ok = line:match("%-%-%s*EXPECT:%s*(.*)")
            if match_ok then expect_val = match_ok end
            
            local match_fail = line:match("%-%-%s*EXPECT_FAIL:%s*(.*)")
            if match_fail then expect_fail_val = match_fail end
        end

        io.write(string.format("运行测试: %-30s ", file))

        --  [新增]：每次编译前，先删掉旧的幽灵二进制！
        os.execute("rm -f native_app")

        -- 调用我们的 l2c 编译
        os.execute("./l2c_bin " .. file .. " > l2c_test.log 2>&1")
        
        --  反例测试逻辑 (Expected Fail)
        if expect_fail_val then
            local f = io.open("native_app", "r")
            if f then
                f:close()
                print(" [FAIL] 预期编译熔断，但竟然生成了可执行文件！防线被击穿！")
                failed = failed + 1
            else
                local log_f = io.open("l2c_test.log", "r")
                local log_content = log_f and log_f:read("*a") or ""
                if log_f then log_f:close() end
                
                -- 使用 plain=true 进行纯文本匹配，防止特殊字符干扰
                if log_content:find(expect_fail_val, 1, true) then
                    print(" [PASS] 成功拦截非法语法！")
                    passed = passed + 1
                else
                    print(" [FAIL] 编译确实失败了，但并非死于预期原因！")
                    print("   期望包含: '" .. expect_fail_val .. "'")
                    print("   实际日志: \n" .. log_content)
                    failed = failed + 1
                end
            end

        --  正例测试逻辑 (Expected Pass)
        else
            -- 假设你在 l2c.lua 里生成了 native_app，我们运行它
            local handle = io.popen("./native_app 2>/dev/null")
            if handle then
                -- 1. 实际输出剔除所有空白字符
                local result = handle:read("*a"):gsub("%s+", "")
                handle:close()
                
                -- 2.  [核心校准]：让期望值在比对前，也同样剔除所有空白字符，实现物理对齐！
                local clean_expect = expect_val and expect_val:gsub("%s+", "") or ""
                
                -- 3. 用洗干净的两端进行终极对齐
                if result == clean_expect then
                    print(" [PASS]")
                    passed = passed + 1
                else
                    print(" [FAIL] 期望: '" .. tostring(expect_val) .. "', 实际: '" .. tostring(result) .. "'")
                    failed = failed + 1
                end
            else
                print(" [FAIL] 编译失败，未生成 native_app")
                failed = failed + 1
            end
        end
    end

    print("========================================")
    print(string.format(" 测试完成 | 通过: %d | 失败: %d", passed, failed))
    print("========================================")
    
    --  [护城河闸刀]：如果有任何测试失败，向操作系统返回失败状态码 (1)，强行掐断 CI/CD 流水线！
    if failed > 0 then
        os.exit(1)
    end

end

run_tests()
