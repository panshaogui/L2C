-- ==============================================================================
-- L2C 极客内建 Profiler & 覆盖率探针
-- ==============================================================================
local M = {}

function M.start()
    local profiler_data = {}
    debug.sethook(function(event)
        local info = debug.getinfo(2, "nS")
        -- 只抓取我们自己 codegen 目录下的器官调用
        if info.source and info.source:match("codegen/") then
            local name = info.name or "<anon>"
            -- 格式化输出：文件名:行号 [函数名]
            local id = string.format("%s:%-4d [%s]", info.source:match("codegen/.*"), info.linedefined, name)
            profiler_data[id] = (profiler_data[id] or 0) + 1
        end
    end, "c") -- "c" 表示在每次 Call 函数时触发

    -- 魔法：利用 Lua 的垃圾回收机制 (__gc) 在程序彻底退出前自动保存报告
    _G.__L2C_PROFILER_SENTINEL = setmetatable({}, { __gc = function()
        local f = io.open("l2c_profile.txt", "w")
        if not f then return end
        f:write("==================================================\n")
        f:write(" L2C 编译器 AST 器官调用热力图与覆盖率报告\n")
        f:write("==================================================\n")
        
        local sorted = {}
        for k, v in pairs(profiler_data) do table.insert(sorted, {k=k, v=v}) end
        table.sort(sorted, function(a, b) return a.v > b.v end) -- 按调用次数降序
        
        for _, item in ipairs(sorted) do
            f:write(string.format("%-50s : %d 次\n", item.k, item.v))
        end
        f:close()
        print(" [L2C 极客探针] AST 覆盖率分析报告已生成: l2c_profile.txt")
    end})
end

return M