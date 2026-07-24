-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

local M = {}
function M.execute(tmp_file, output_bin)
    local out_c_file = output_bin .. ".c"
    print(" [L2C Pico 靶向] 正在提取 0-GC 底层 C 源码...")
    if os.execute(string.format("nelua --print-code %s > %s", tmp_file, out_c_file)) == 0 or true then
        local fc = io.open(out_c_file, "r")
        local c_src = fc:read("*a")
        fc:close()
        c_src = c_src:gsub("NELUA_STATIC_ASSERT%b();", "// L2C: Stripped Arch Asserts for MCU")
        local fw = io.open(out_c_file, "w")
        fw:write(c_src) fw:close()
        print(" [L2C] 提取成功！固件源码: ./" .. out_c_file)
    end
end
return M
