-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

local IS_WINDOWS = package.config:sub(1,1) == "\\"

print(" [L2C Super Forge] 启动跨平台绝对主权单体锻造...")

local function get_files(dir, ext)
    local t = {}
    local cmd = IS_WINDOWS and ('dir /S /B /A:-D "' .. dir:gsub("/", "\\") .. '" 2>nul') or ('find ' .. dir .. ' -type f 2>/dev/null')
    local f = io.popen(cmd)
    if f then
        for line in f:lines() do
            if not ext or line:match(ext) then table.insert(t, (line:gsub("\\", "/"))) end
        end
        f:close()
    end
    return t
end

-- 1. 启动 VFS 打包器子模块
dofile("tools/pack_assets.lua")

print("\n  召唤 C 编译器进行终极封测...")

-- 2. 动态搜集所有 C 语言原材料 (包括完整的 Lua 虚拟机源码！)
local c_sources = {
    "clib/l2c_bootstrap.c",
    "clib/nelua_runtime/lfs.c",
    "clib/nelua_runtime/hasher.c",
    "clib/nelua_runtime/sys.c"
}

-- 核心修复 1：把刚才遗忘的 Lua 内核源码重新加进来！(排除自带 main 的 lua.c 和 luac.c)
for _, f in ipairs(get_files("clib/nelua_runtime/lua", "%.c$")) do
    if not f:match("lua%.c$") and not f:match("luac%.c$") then 
        table.insert(c_sources, f) 
    end
end

-- 核心修复 2：搜集 LPeg 源码
for _, f in ipairs(get_files("clib/nelua_runtime/lpeglabel", "%.c$")) do
    table.insert(c_sources, f)
end

local all_c_src = table.concat(c_sources, " ")

-- 核心修复 3：头文件包含路径，只指向我们自己的 clib 目录！绝不使用系统的 /opt 路径！
local includes = "-Iclib/nelua_runtime/lua -Iclib/nelua_runtime/lpeglabel"
local libs = IS_WINDOWS and "" or "-lm -ldl"
local out_bin = IS_WINDOWS and "l2c_bin.exe" or "l2c_bin"

-- 终极纯净弹匣：完全独立于系统环境！只要有 gcc/clang 就能成功！
local compile_cmds = {
    -- 1. 绝对主权静态封印 (Alpine/Musl/Linux 的最爱，彻底斩断环境依赖！)
    string.format("clang -O3 -flto %s %s %s -static -o %s 2>/dev/null", includes, all_c_src, libs, out_bin),
    string.format("gcc -O3 -flto %s %s %s -static -o %s 2>/dev/null", includes, all_c_src, libs, out_bin),
    
    -- 2. 动态链接 (Mac Apple Silicon / Intel 的唯一出路，Ubuntu Glibc 备用)
    string.format("clang -O3 -flto %s %s %s -o %s 2>/dev/null", includes, all_c_src, libs, out_bin),
    string.format("gcc -O3 -flto %s %s %s -o %s 2>/dev/null", includes, all_c_src, libs, out_bin),
    
    -- 3. 去除 LTO 的安全降级版本 (针对编译链不完整的残缺环境)
    string.format("clang -O3 %s %s %s -o %s 2>/dev/null", includes, all_c_src, libs, out_bin),
    string.format("gcc -O3 %s %s %s -o %s 2>/dev/null", includes, all_c_src, libs, out_bin)
}

local res = false
local last_cmd = ""
for _, cmd in ipairs(compile_cmds) do
    print("    探针射击: " .. cmd:gsub(" 2>/dev/null", ""))
    local status = os.execute(cmd)
    if status == 0 or status == true then
        res = true
        break
    end
    last_cmd = cmd:gsub(" 2>/dev/null", "")
end

if res then
    os.execute("rm -f clib/l2c_bundle.h")
    print("\n 盗梦空间完美闭环！独立的 L2C 原生二进制已生成: ./" .. out_bin)
else
    print("\n [致命错误] 所有编译探针均失效！底层 C 编译器原始报错如下：")
    os.execute(last_cmd)
    os.exit(1)
end