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
    local final_code = "## pragma { gc = 'none' }\n" .. deps.cincludes .. "require 'allocators.arena'\nglobal my_arena: ArenaAllocator(10 * 1024 * 1024)\n\n" .. nelua_code

    local tmp_file = ".l2c_temp_" .. os.time() .. ".nelua"
    local f_out = io.open(tmp_file, "w")
    f_out:write(final_code) f_out:close()
    return tmp_file
end
return M
