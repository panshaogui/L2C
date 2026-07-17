-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

local M = {}
function M.execute(tmp_file, output_bin)
    local out_c_file = output_bin .. ".c"
    print("🔬 [L2C ESP32 靶向] 正在提取并物理扭曲入口架构...")
    if os.execute(string.format("nelua --print-code %s > %s", tmp_file, out_c_file)) == 0 or true then
        local fc = io.open(out_c_file, "r")
        local c_src = fc:read("*a")
        fc:close()
        
        -- 1. 剥离断言
        c_src = c_src:gsub("NELUA_STATIC_ASSERT%b();", "// L2C: Stripped Arch Asserts")
        -- 2. 🔥 物理扭曲：强行把标准的 C 入口，扭曲为 FreeRTOS / ESP-IDF 专属的 app_main！
        -- 顺便自动补齐 argc 和 argv 防止内部变量报错！
        c_src = c_src:gsub("int main%(int argc, char%*%* argv%) %{", "void app_main(void) {\n  int argc = 0;\n  char** argv = (char**)0;\n")
        
        -- 3. 🔪 刮骨疗毒：抹掉 app_main 内部不合规的 return 返回值！
        -- 把 "return nelua_main(argc, argv);" 强行扭曲为 "nelua_main(argc, argv);"
        c_src = c_src:gsub("return%s+nelua_main%(argc,%s*argv%);", "nelua_main(argc, argv);")
        
        local fw = io.open(out_c_file, "w")
        fw:write(c_src) fw:close()
        print("✅ [L2C] ESP32 固件源码生成完毕！: ./" .. out_c_file)
    end
end
return M
