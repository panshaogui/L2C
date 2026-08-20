-- ==============================================================================
-- L2C VFS Matrix Encoder (全内存虚拟文件系统打包器)
-- ==============================================================================
print(" [L2C Matrix] 正在将所有 Lua 源码压缩为 C 内存数组...")

local out = io.open("clib/l2c_bundle.h", "w")
out:write("// L2C Auto-Generated VFS & Preload Matrix (DO NOT EDIT!)\n")
out:write("#pragma once\n#include <lua.h>\n#include <lauxlib.h>\n\n")

-- 扫描所有需要封印的目录
local function get_files(cmd)
    local t = {}
    local f = io.popen(cmd)
    for l in f:lines() do table.insert(t, l) end
    f:close()
    return t
end

-- 囊括 L2C 大脑、Teal、Nelua 源码与标准库
local files = get_files('find codegen l2c_cli std libs -type f 2>/dev/null')
table.insert(files, "l2c.lua")

out:write("static void l2c_preload_assets(lua_State *L) {\n")
out:write('  luaL_dostring(L, "_G.L2C_VFS = {}");\n')

for i, file in ipairs(files) do
    local f = io.open(file, "rb")
    local content = f:read("*a")
    f:close()

    -- 1. 将源码转为 C 数组
    out:write(string.format("  static const unsigned char f_%d[] = {", i))
    for j = 1, #content do
        out:write(string.format("0x%02x,", string.byte(content, j)))
    end
    out:write("0x00};\n") -- 终止符

    -- 2. 注入 package.preload (供内存 require)
    if file:match("%.lua$") then
        local modname = file:gsub("^libs/nelua/lualib/", ""):gsub("^libs/", ""):gsub("%.lua$", ""):gsub("/", ".")
        modname = modname:gsub("^codegen%.", "codegen."):gsub("^l2c_cli%.", "l2c_cli."):gsub("^l2c$", "l2c")
        
        out:write(string.format('  lua_getglobal(L, "package"); lua_getfield(L, -1, "preload");\n'))
        out:write(string.format('  luaL_loadbuffer(L, (const char*)f_%d, %d, "@%s");\n', i, #content, file))
        out:write(string.format('  lua_setfield(L, -2, "%s"); lua_pop(L, 2);\n', modname))
    end

    -- 3. 注入 _G.L2C_VFS (供 Teal 和 Nelua 跨维读取文件)
    out:write(string.format('  lua_getglobal(L, "L2C_VFS");\n'))
    out:write(string.format('  lua_pushlstring(L, (const char*)f_%d, %d);\n', i, #content))
    out:write(string.format('  lua_setfield(L, -2, "%s"); lua_pop(L, 1);\n', file))
end

out:write("}\n")
out:close()
print(" [L2C Matrix] 打包完毕！已生成 clib/l2c_bundle.h")
