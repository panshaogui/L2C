-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

local tl = require("tl")
local Codegen = require("codegen.core")
local Forge = require("l2c_cli.hardware_forge")
local M = {}

function M.build_nelua(bundled_code, deps, input_file)
    local env = tl.init_env()
    local result = tl.process_string(bundled_code, false, env, input_file)
    if #result.syntax_errors > 0 or #result.type_errors > 0 then
        print("\n========================================================")
        print(" [L2C 前端熔断] Teal 静态类型与语法护城河拦截！")
        print("   -> 判决: 代码在降维至物理 C 源码前，未能通过严格的前端安全审查。")
        
        if #result.syntax_errors > 0 then
            print("   ->  致命语法错误 (Syntax Errors):")
            for _, err in ipairs(result.syntax_errors) do 
                local loc = (err.y and err.x) and string.format("[行 %d, 列 %d]", err.y, err.x) or ""
                print("      " .. loc .. " " .. err.msg) 
            end
        end
        
        if #result.type_errors > 0 then
            print("   ->  强类型约束违规 (Type Errors):")
            for _, err in ipairs(result.type_errors) do 
                local loc = (err.y and err.x) and string.format("[行 %d, 列 %d]", err.y, err.x) or ""
                print("      " .. loc .. " " .. err.msg) 
            end
        end

        local dump_file = ".l2c_error_dump.tl"
        local f_dump = io.open(dump_file, "w")
        if f_dump then
            f_dump:write(bundled_code) 
            f_dump:close()
            print("   ->  追溯现场: 已将展开后的全量源码 Dump 至 " .. dump_file)
        end
        print("========================================================\n")
        os.exit(1)
    end

    local engine = Codegen.new()
    local nelua_code = engine:gen(result.ast)
    
    -- 模块配置并组装
    local cfg = Forge.sniff_and_forge(bundled_code)
    local final_code = Forge.assemble_system(cfg, deps, nelua_code)

    local tmp_file = ".l2c_temp_" .. os.time() .. ".nelua"
    local f_out = io.open(tmp_file, "w")
    f_out:write(final_code) f_out:close()
    return tmp_file
end

return M
