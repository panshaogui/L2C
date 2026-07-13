-- tests/unit/unit_runner.lua
-- 🎯 路径向外翻两级，确保所有单体测试能找到 codegen
package.path = package.path .. ";./?.lua;../?.lua;../../?.lua;./codegen/?.lua;../codegen/?.lua"

local M = {}

function M.run()
    -- 利用你习惯的 find 命令，只捞单体测试
    local p = io.popen('find "tests/unit" -type f -name "test_*.lua"')
    local test_files = {}
    for file in p:lines() do table.insert(test_files, file) end
    p:close()
    
    table.sort(test_files)
    
    local passed, failed = 0, 0
    print("\n📡 [Phase 1] 正在轰炸单模块白盒测试 (Unit Tests)...")
    print("----------------------------------------")
    
    for _, file in ipairs(test_files) do
        -- 把路径转换为 require 格式，比如 tests/unit/test_flow.lua -> tests.unit.test_flow
        local mod_name = file:gsub("%.lua$", ""):gsub("/", ".")
        io.write(string.format("运行单体: %-25s ", mod_name))
        
        -- 清除之前的缓存，保证每次require都是新鲜的代码
        package.loaded[mod_name] = nil
        local success, err = pcall(require, mod_name)
        
        if success then
            print("✅ [PASS]")
            passed = passed + 1
        else
            print("❌ [FAIL]\n\t[错误详情]: " .. tostring(err))
            failed = failed + 1
        end
    end
    
    print("----------------------------------------")
    print(string.format("🟢 单体测试完成 | 通过: %d | 失败: %d", passed, failed))
    return failed == 0 -- 如果没有失败，返回 true
end

-- 只有直接运行它时才跑（方便单独调试单元测试）
if arg and arg[0]:match("unit_runner.lua$") then
    M.run()
end

return M
