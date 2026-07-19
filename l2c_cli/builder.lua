-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

local tl = require("tl")
local Codegen = require("codegen.core")
local M = {}

function M.build_nelua(bundled_code, deps, input_file)
    local env = tl.init_env()
    local result = tl.process_string(bundled_code, false, env, input_file)
    if #result.syntax_errors > 0 or #result.type_errors > 0 then
        print("❌ Teal 语法/类型检查失败:")
        for _, err in ipairs(result.syntax_errors) do print("  [语法错误]:", err.msg) end
        for _, err in ipairs(result.type_errors) do print("  [类型错误]:", err.msg) end
        local f_dump = io.open(".l2c_error_dump.tl", "w")
        f_dump:write(bundled_code) f_dump:close()
        os.exit(1)
    end

    local engine = Codegen.new()
    local nelua_code = engine:gen(result.ast)
    
    -- 📡 核心降维魔法：靶向智能伸缩！嗅探代码，看菜下饭！
    local arena_size = "10 * 1024 * 1024" -- 默认 PC/高频环境，分配 10MB
    
    if bundled_code:match("std/pico%.tl") then
        arena_size = "32 * 1024"  -- 树莓派 Pico 极度贫穷，只给 32KB
        print("⚙️  [L2C 内存雷达] 嗅探到 Pico 靶向，Arena 智能缩容至 32 KB！")
    elseif bundled_code:match("std/esp32%.tl") or bundled_code:match("std/freertos%.tl") then
        arena_size = "64 * 1024"  -- ESP32 稍微富裕，给 64KB
        print("⚙️  [L2C 内存雷达] 嗅探到 ESP32/FreeRTOS 靶向，Arena 智能缩容至 64 KB！")
    end

    -- 将动态缩容后的大小注入到底层模板
    local final_code = string.format([[
        ## pragma { gc = 'none' }
        %s
        require 'allocators.arena'
        global my_arena: ArenaAllocator(%s)

        %s
        ]], deps.cincludes, arena_size, nelua_code)

    local tmp_file = ".l2c_temp_" .. os.time() .. ".nelua"
    local f_out = io.open(tmp_file, "w")
    f_out:write(final_code) f_out:close()
    return tmp_file
end

return M
