-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

local M = {}
function M.execute(tmp_file, output_bin, deps)
    local out_c_file = output_bin .. ".c"
    print(" [L2C ESP32 靶向] 正在提取并物理扭曲入口架构...")
    
    -- 替换外部调用为全内存融合调用
    if _G.L2C_Nelua_Run({"--print-code", tmp_file}, out_c_file) then
        local fc = io.open(out_c_file, "r")
        local c_src = fc:read("*a")
        fc:close()
        
        c_src = c_src:gsub("NELUA_STATIC_ASSERT%b();", "// L2C: Stripped Arch Asserts")
        c_src = c_src:gsub("int main%(int argc, char%*%* argv%) %{", "void app_main(void) {\n  int argc = 0;\n  char** argv = (char**)0;\n")
        c_src = c_src:gsub("return%s+nelua_main%(argc,%s*argv%);", "nelua_main(argc, argv);")
        
        -- 终极物理注射：将 @l2c_source 的 C 源码直接追加到底部！
        if deps and deps.cpp_sources then
            for _, src_file in ipairs(deps.cpp_sources) do
                local inject_code = _G.L2C_VFS and _G.L2C_VFS[src_file]
                if not inject_code then
                    local f_src = io.open(src_file, "r")
                    if f_src then inject_code = f_src:read("*a"); f_src:close() end
                end
                
                if inject_code then
                    c_src = c_src .. "\n\n// =========================================================================\n"
                    c_src = c_src .. "// L2C UNITY BUILD: Injected C Source -> " .. src_file .. "\n"
                    c_src = c_src .. "// =========================================================================\n\n"
                    c_src = inject_code .. "\n" .. c_src 
                    print(" [L2C 物理注射] 已将 C 源码融进主固件: " .. src_file)
                else
                    print(" [L2C 警告] 找不到请求注入的 C 源码: " .. src_file)
                end
            end
        end

        local fw = io.open(out_c_file, "w")
        fw:write(c_src) fw:close()
        print(" [L2C] ESP32 固件源码生成完毕！: ./" .. out_c_file)
    else
        print(" [L2C 熔断] ESP32 内存 C 提取失败！")
    end
end
return M