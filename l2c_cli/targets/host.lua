-- ==============================================================================
-- Copyright (c) 2026 L2C Architect | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

local M = {}
local bundler = require("l2c_cli.bundler")

function M.execute(tmp_file, output_bin, deps)
    print("⚙️  [L2C HOST 靶向] 启动 Clang/GCC 极限硬件优化...")

    -- 1. 环境嗅探
    local is_musl = os.getenv("L2C_MUSL_FORGE") == "1"
    local sys_inc = is_musl and "/usr/include" or "/opt/homebrew/include"
    local sys_lib = is_musl and "/usr/lib" or "/opt/homebrew/lib"
    local project_pwd = os.getenv("PWD") or "."

    -- 2. 雷达总线配置
    local mac_cflags    = string.format(" -I%s -I%s -I%s/bin -I%s/std -I%s/examples -I%s/clib", sys_inc, project_pwd, project_pwd, project_pwd, project_pwd, project_pwd)
    local mac_ldflags   = ""
    local extra_ldflags = ""
    local extra_cflags  = ""
    local final_ldflags = deps.ldflags

    -- 3. 静态链接接管与隐形债务偿还
    if final_ldflags ~= "" then
        local static_libs = ""
        local dynamic_libs = ""
        local seen_libs = {}

        for lib in final_ldflags:gmatch("%-l([%w_%-]+)") do
            if not seen_libs[lib] then
                seen_libs[lib] = true
                local static_path = sys_lib .. "/lib" .. lib .. ".a"
                local f_check = io.open(static_path, "r")

                -- 查账本
                local std_key = "std/" .. lib .. ".tl"
                local debt = bundler.STD_DEBT[std_key]
                if debt then
                    local resolved_ldflags = debt.ldflags
		    -- 🔥 [平台感知与智能换汇]：解决 C++ 标准库碎片化惨案！
                    if is_musl then
                        -- Alpine Linux/GNU 环境下，将 LLVM 的 libc++ 智能转换为 GNU 的 libstdc++
                        resolved_ldflags = resolved_ldflags:gsub("%-lc%+%+", "-lstdc++")
                    
                        -- 如果是纯静态封印，C++ 标准库也必须物理打进包里
                        if resolved_ldflags:match("%-lstdc%+%+") then
                            resolved_ldflags = resolved_ldflags .. " -static-libstdc++ -static-libgcc"
                        end
                    end
		    print(string.format("   🛡️  [雷达触发] 检测到 %s 依赖链，环境感知自动偿还隐形债: %s", std_key, resolved_ldflags))
		    extra_ldflags = extra_ldflags .. resolved_ldflags
                    extra_cflags  = extra_cflags  .. debt.cflags
                end

                if f_check then
                    f_check:close()
                    print("🔗 [L2C 物理拦截] 成功捕获静态库: " .. static_path)
                    static_libs = static_libs .. " " .. static_path
                else
                    print(string.format("⚠️  [L2C 降级] 未找到静态 lib%s.a，退化为动态链接模式。", lib))
                    dynamic_libs = dynamic_libs .. " -l" .. lib
                end
            end
        end

        final_ldflags = static_libs .. " " .. dynamic_libs .. extra_ldflags
        mac_ldflags = "-L" .. sys_lib .. " "
        mac_cflags  = mac_cflags .. extra_cflags

        if is_musl then mac_ldflags = mac_ldflags .. "-static " end
    end

    -- 4. C/C++ 胶水层外包编译
    local extra_objs = ""
    for _, src in ipairs(deps.cpp_sources) do
        local obj = src:gsub("%.cpp$", ".o"):gsub("%.c$", ".o")
        print("🔨 [L2C 外包编译] 正在锻造 C/C++ 胶水层: " .. src)
        local cc_cmd = src:match("%.cpp$") and "clang++ -std=c++17" or "clang"
        local build_obj_cmd = string.format("%s -O3 -march=native -c %s -o %s %s", cc_cmd, src, obj, mac_cflags)
        
        local res = os.execute(build_obj_cmd)
        if res ~= 0 and res ~= true then
            print("❌ 胶水层编译失败: " .. src)
            os.exit(1)
        end
        extra_objs = extra_objs .. " " .. obj
    end

    -- 5. 终极一波流物理连结！
    local compile_cmd = string.format(
        "nelua --cc=clang --cflags='-O3 -march=native -flto%s' --ldflags='%s %s %s' -o %s %s", 
        mac_cflags, mac_ldflags, final_ldflags, extra_objs, output_bin, tmp_file
    )

    local exit_code = os.execute(compile_cmd)
    
    -- 打扫外包的 C++ 临时文件
    os.execute("rm -f clib/*.o 2>/dev/null")

    if exit_code == 0 or exit_code == true then
        print(string.format("✅ [L2C] 编译完美收官！终极主权二进制已生成: ./%s", output_bin))
        os.execute("ls -lh " .. output_bin .. " | awk '{print \"📦 物理体积: \" $5}'")
    else
        print("❌ [L2C] 底层 C 编译失败，请检查语法兼容性。")
    end
end

return M
