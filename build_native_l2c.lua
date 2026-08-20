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

-- 准备所有的源文件
local preload_files = {} -- 需要放入 package.preload 的 Lua 代码
local vfs_files = {}     -- 需要放入 L2C_VFS 的资源文件

local function add_preload(mod_name, path)
    local f = io.open(path, "r"); if not f then print(" 找不到 " .. path); os.exit(1) end
    table.insert(preload_files, { mod = mod_name, code = f:read("*a"), path = path })
    f:close()
    print(" -> 已物理封印外部库/模块: " .. mod_name)
end

-- 1. 物理封印本地 libs/ 目录下的依赖，彻底切断对宿主机全局环境的依赖！
add_preload("tl", "libs/tl.lua")
add_preload("inspect", "libs/inspect.lua")

-- 2. 封印 L2C 引擎与 Nelua 核心
for _, dir in ipairs({"codegen", "l2c_cli"}) do
    for _, p in ipairs(get_files(dir, "%.lua$")) do
        local mod = p:gsub("^%./", ""):gsub("/", "."):gsub("%.lua$", "")
        add_preload(mod, p)
    end
end
for _, p in ipairs(get_files("libs/nelua/lualib", "%.lua$")) do
    local mod = p:gsub("^libs/nelua/lualib/", ""):gsub("%.lua$", ""):gsub("/", ".")
    add_preload(mod, p)
end
-- L2C 核心入口
add_preload("l2c", "l2c.lua")

-- 3. 封印 VFS 标准库
for _, p in ipairs(get_files("std")) do
    local f = io.open(p, "r"); table.insert(vfs_files, { path = p, code = f:read("*a") }); f:close()
    print(" -> 已物理封印 VFS 库: " .. p)
end
for _, p in ipairs(get_files("libs/nelua/lib")) do
    local vfs_path = p:gsub("^libs/nelua/", "")
    local f = io.open(p, "r"); table.insert(vfs_files, { path = vfs_path, code = f:read("*a") }); f:close()
end

-- ============================================================================
-- 生成 C 源码文件 l2c_main.c
-- ============================================================================
print("\n  正在将所有源码编译为 C 字节数组 (luaL_loadbuffer 安全模式)...")
local out = io.open("l2c_main.c", "w")

out:write([[
#include <stdio.h>
#include <stdlib.h>
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

int luaopen_lpeglabel(lua_State *L);
int luaopen_lfs(lua_State *L);
int luaopen_sys(lua_State *L);
int luaopen_hasher(lua_State *L);

static void l2c_preload_assets(lua_State *L) {
    luaL_dostring(L, "_G.L2C_VFS = {}");
]])

local all_assets = {}
for _, v in ipairs(preload_files) do table.insert(all_assets, v) end
for _, v in ipairs(vfs_files) do table.insert(all_assets, v) end

-- 写入十六进制数组
for i, asset in ipairs(all_assets) do
    out:write(string.format("  static const unsigned char f_%d[] = {", i))
    for j = 1, #asset.code do out:write(string.format("0x%02x,", string.byte(asset.code, j))) end
    out:write("0x00};\n")
    
    if asset.mod then
        out:write(string.format('  lua_getglobal(L, "package"); lua_getfield(L, -1, "preload");\n'))
        out:write(string.format('  luaL_loadbuffer(L, (const char*)f_%d, %d, "@%s");\n', i, #asset.code, asset.path))
        out:write(string.format('  lua_setfield(L, -2, "%s"); lua_pop(L, 2);\n', asset.mod))
        
        -- 双重复写兼容
        local short_name = asset.mod:gsub("^codegen%.", ""):gsub("^l2c_cli%.", "")
        if short_name ~= asset.mod then
            out:write(string.format('  lua_getglobal(L, "package"); lua_getfield(L, -1, "preload");\n'))
            out:write(string.format('  lua_getfield(L, -1, "%s"); lua_setfield(L, -2, "%s"); lua_pop(L, 2);\n', asset.mod, short_name))
        end
    else
        out:write(string.format('  lua_getglobal(L, "L2C_VFS");\n'))
        out:write(string.format('  lua_pushlstring(L, (const char*)f_%d, %d);\n', i, #asset.code))
        out:write(string.format('  lua_setfield(L, -2, "%s"); lua_pop(L, 1);\n', asset.path))
    end
end

out:write("}\n\n")

-- 写入主函数
out:write([[
int main(int argc, char** argv) {
    lua_State *L = luaL_newstate();
    luaL_openlibs(L);

    luaL_requiref(L, "lpeglabel", luaopen_lpeglabel, 1); lua_pop(L, 1);
    luaL_requiref(L, "lfs", luaopen_lfs, 1); lua_pop(L, 1);
    luaL_requiref(L, "sys", luaopen_sys, 1); lua_pop(L, 1);
    luaL_requiref(L, "hasher", luaopen_hasher, 1); lua_pop(L, 1);

    lua_newtable(L);
    for(int i = 0; i < argc; i++) {
        lua_pushstring(L, argv[i]);
        lua_rawseti(L, -2, i); 
    }
    lua_setglobal(L, "arg");

    l2c_preload_assets(L);

    if (luaL_dostring(L, "require('l2c')") != LUA_OK) {
        fprintf(stderr, " L2C 内核崩溃: %s\n", lua_tostring(L, -1));
        lua_close(L);
        return 1;
    }

    lua_close(L);
    return 0;
}
]])
out:close()

-- ============================================================================
-- 阶段 3：执行 GCC/Clang 熔炼 (真正的 100% 源码级自举，0 系统依赖！)
-- ============================================================================
print("\n  召唤 C 编译器进行终极封测...")

-- 1. 动态搜集所有 C 语言原材料 (包括完整的 Lua 虚拟机源码！)
local c_sources = {
    "l2c_main.c",
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
    string.format("clang -O3 -flto %s %s %s -o %s 2>/dev/null", includes, all_c_src, libs, out_bin),
    string.format("gcc -O3 -flto %s %s %s -o %s 2>/dev/null", includes, all_c_src, libs, out_bin),
    -- 去除 LTO 的安全降级版本
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
    os.execute("rm l2c_main.c")
    print("\n 盗梦空间完美闭环！独立的 L2C 原生二进制已生成: ./" .. out_bin)
else
    print("\n [致命错误] 所有编译探针均失效！底层 C 编译器原始报错如下：")
    os.execute(last_cmd)
    os.exit(1)
end