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
                -- 核心修复：通过 Source Map 逆向追溯真实物理文件与行号
                local bundle_y = err.y or 0
                local real_loc = deps.line_map and deps.line_map[bundle_y]
                local file_str = real_loc and real_loc.file or "unknown"
                local line_str = real_loc and real_loc.line or bundle_y
                local loc = string.format("[%s | 行 %s, 列 %s]", file_str, line_str, err.x or "?")
                print("      " .. loc .. " " .. err.msg) 
            end
        end
        
        if #result.type_errors > 0 then
            print("   ->  强类型约束违规 (Type Errors):")
            for _, err in ipairs(result.type_errors) do 
                local bundle_y = err.y or 0
                local real_loc = deps.line_map and deps.line_map[bundle_y]
                local file_str = real_loc and real_loc.file or "unknown"
                local line_str = real_loc and real_loc.line or bundle_y
                local loc = string.format("[%s | 行 %s, 列 %s]", file_str, line_str, err.x or "?")
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

    -- 核心修复：把合并后的源码和 Source Map 一起交给编译器大脑！
    local engine = Codegen.new(bundled_code, deps.line_map)
    local nelua_code = engine:gen(result.ast)

    -- [HLS PIO 物理闭环]：如果存在拦截的 PIO 硬件状态机，执行锻造与头文件注入
    if engine.pio_registry and next(engine.pio_registry) then
        local pio_out = {}
        for pio_name, pio_asm in pairs(engine.pio_registry) do
            table.insert(pio_out, ".program " .. pio_name)
            table.insert(pio_out, pio_asm)
            table.insert(pio_out, "\n")
        end
        local pio_file = io.open("l2c_hardware.pio", "w")
        if pio_file then
            pio_file:write(table.concat(pio_out, "\n"))
            pio_file:close()
            -- 强制向 C 宇宙顶部注入 PIO 编译后的头文件
            nelua_code = "## cinclude 'l2c_hardware.pio.h'\n" .. nelua_code
        end
    end
    
    -- [HLS Verilog 物理闭环]：如果存在拦截的 HDL 电路，执行锻造并吐出 .v 文件
    if engine.verilog_registry and next(engine.verilog_registry) then
        local v_out = {}
        for mod_name, v_code in pairs(engine.verilog_registry) do
            table.insert(v_out, "// L2C HLS Generated RTL Module: " .. mod_name)
            table.insert(v_out, v_code)
            table.insert(v_out, "\n")
        end
        local v_file = io.open("l2c_hardware.v", "w")
        if v_file then
            v_file:write(table.concat(v_out, "\n"))
            v_file:close()
            print(" [L2C HDL Forge] 纯硬连线 Verilog 数字电路综合完毕: l2c_hardware.v")
        end
    end

    -- 模块配置并组装
    local cfg = Forge.sniff_and_forge(bundled_code)
    local final_code = Forge.assemble_system(cfg, deps, nelua_code)

    local tmp_file = ".l2c_temp_" .. os.time() .. ".nelua"
    local f_out = io.open(tmp_file, "w")
    f_out:write(final_code) f_out:close()
    return tmp_file
end

return M

