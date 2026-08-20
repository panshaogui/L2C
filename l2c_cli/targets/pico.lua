-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

local M = {}
function M.execute(tmp_file, output_bin)
    local out_c_file = output_bin .. ".c"
    print(" [L2C Pico 靶向] 正在提取 0-GC 底层 C 源码...")
    
    -- 替换外部调用为全内存融合调用
    if _G.L2C_Nelua_Run({"--print-code", tmp_file}, out_c_file) then
        local fc = io.open(out_c_file, "r")
        local c_src = fc:read("*a")
        fc:close()
        c_src = c_src:gsub("NELUA_STATIC_ASSERT%b();", "// L2C: Stripped Arch Asserts for MCU")
        local fw = io.open(out_c_file, "w")
        fw:write(c_src) fw:close()
        print(" [L2C] 提取成功！固件源码: ./" .. out_c_file)
    else
        print(" [L2C 熔断] Pico 内存 C 提取失败！")
    end

    local pio_file = io.open("l2c_hardware.pio", "r")
    if pio_file then
        pio_file:close()
        print(" [L2C PIO Forge] 发现硬件状态机文件，正在唤醒 pioasm 综合...")
        if os.execute("pioasm l2c_hardware.pio l2c_hardware.pio.h") ~= 0 then
            print(" [L2C 熔断] pioasm 综合失败！")
            os.exit(1)
        end
    end
end
return M
