-- ==============================================================================
-- L2C VFS Matrix Encoder (全内存虚拟文件系统打包器)
-- ==============================================================================
local IS_WINDOWS = package.config:sub(1,1) == "\\"

local function get_files(dir, ext)
    local t = {}
    local cmd = IS_WINDOWS and ('dir /S /B /A:-D "' .. dir:gsub("/", "\\") .. '" 2>nul') or ('find ' .. dir .. ' -type f 2>/dev/null')
    local f = io.popen(cmd)
    if f then for line in f:lines() do if not ext or line:match(ext) then table.insert(t, (line:gsub("\\", "/"))) end end f:close() end
    return t
end

local function read_lua_source(path)
    local f = io.open(path, "r"); if not f then return "" end
    local code = f:read("*a"); f:close()
    return code
end

print(" [L2C Packer] 正在收集并编码 Lua 源码...")
local preload_files, vfs_files = {}, {}

local function add_preload(mod_name, path)
    table.insert(preload_files, { mod = mod_name, code = read_lua_source(path), path = path })
end

add_preload("tl", "libs/tl.lua")
add_preload("inspect", "libs/inspect.lua")
add_preload("l2c", "l2c.lua")

for _, dir in ipairs({"codegen", "l2c_cli"}) do
    for _, p in ipairs(get_files(dir, "%.lua$")) do add_preload(p:gsub("^%./", ""):gsub("/", "."):gsub("%.lua$", ""), p) end
end
for _, p in ipairs(get_files("libs/nelua/lualib", "%.lua$")) do add_preload(p:gsub("^libs/nelua/lualib/", ""):gsub("%.lua$", ""):gsub("/", "."), p) end
for _, p in ipairs(get_files("std")) do table.insert(vfs_files, { path = p, code = read_lua_source(p) }) end
for _, p in ipairs(get_files("libs/nelua/lib")) do table.insert(vfs_files, { path = p:gsub("^libs/nelua/", ""), code = read_lua_source(p) }) end

local out = io.open("clib/l2c_bundle.h", "w")
out:write("// L2C Auto-Generated VFS Matrix\n#pragma once\n#include <lua.h>\n#include <lauxlib.h>\n\nstatic void l2c_preload_assets(lua_State *L) {\n  luaL_dostring(L, \"_G.L2C_VFS = {}\");\n")

local all_assets = {}
for _, v in ipairs(preload_files) do table.insert(all_assets, v) end
for _, v in ipairs(vfs_files) do table.insert(all_assets, v) end

for i, asset in ipairs(all_assets) do
    out:write(string.format("  static const unsigned char f_%d[] = {", i))
    for j = 1, #asset.code do out:write(string.format("0x%02x,", string.byte(asset.code, j))) end
    out:write("0x00};\n")
    if asset.mod then
        out:write(string.format('  lua_getglobal(L, "package"); lua_getfield(L, -1, "preload");\n  luaL_loadbuffer(L, (const char*)f_%d, %d, "@%s");\n  lua_setfield(L, -2, "%s"); lua_pop(L, 2);\n', i, #asset.code, asset.path, asset.mod))
        local short_name = asset.mod:gsub("^codegen%.", ""):gsub("^l2c_cli%.", "")
        if short_name ~= asset.mod then
            out:write(string.format('  lua_getglobal(L, "package"); lua_getfield(L, -1, "preload");\n  lua_getfield(L, -1, "%s"); lua_setfield(L, -2, "%s"); lua_pop(L, 2);\n', asset.mod, short_name))
        end
    else
        out:write(string.format('  lua_getglobal(L, "L2C_VFS");\n  lua_pushlstring(L, (const char*)f_%d, %d);\n  lua_setfield(L, -2, "%s"); lua_pop(L, 1);\n', i, #asset.code, asset.path))
    end
end
out:write("}\n")
out:close()
print(" [L2C Packer] VFS 矩阵打包完毕！")