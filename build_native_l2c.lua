-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- build_native_l2c.lua：盗梦空间级 C 语言外壳嵌入器
local function get_files(dir)
    local p = io.popen('find "'..dir..'" -type f -name "*.lua" 2>/dev/null')
    local files = {}
    if p then
        for file in p:lines() do table.insert(files, file) end
        p:close()
    end
    return files
end

print("==================================================")
print("📦 1. 正在提取 L2C 核心引擎与器官并焊入 Preload 矩阵...")
print("==================================================")
local bundled_code = ""

--  [自依赖降维打击]：自动在当前系统中寻找 tl 和 inspect 的源码物理位置，生吞它们！
local function bundle_vendor(mod_name)
    local path = package.searchpath(mod_name, package.path)
    if not path then
        print("❌ 致命错误：本机找不到依赖库 " .. mod_name)
        os.exit(1)
    end
    local f = io.open(path, "r")
    local code = f:read("*a")
    f:close()
    bundled_code = bundled_code .. string.format("package.preload['%s'] = function()\n%s\nend\n", mod_name, code)
    print(" -> 已物理封印外部库: " .. mod_name .. " (来自 " .. path .. ")")
end

bundle_vendor("tl")
bundle_vendor("inspect")

local files = get_files("codegen")
for _, path in ipairs(files) do
    -- 兼容不管是 codegen/ 还是 compiler/codegen/
    local mod_name = path:gsub("^%./", ""):gsub("/", "."):gsub("%.lua$", "")
    local f = io.open(path, "r")
    local code = f:read("*a")
    f:close()
    
    -- 注入双重复写，确保不管是用 require("codegen.xxx") 还是 require("xxx") 都能精准击中
    bundled_code = bundled_code .. string.format("package.preload['%s'] = function()\n%s\nend\n", mod_name, code)
    local short_name = mod_name:gsub("^codegen%.", "")
    if short_name ~= mod_name then
        bundled_code = bundled_code .. string.format("package.preload['%s'] = package.preload['%s']\n", short_name, mod_name)
    end
    print(" -> 已物理封印器官: " .. mod_name)
end

-- 封印主入口
local f_main = io.open("l2c.lua", "r")
bundled_code = bundled_code .. "\n-- [[ L2C 主引擎核心入口 ]] \n" .. f_main:read("*a")
f_main:close()

print("\n🧬 2. 正在将 Lua 源码编码为纯 C 物理字节流 (防转义逃逸)...")
local c_hex = {}
for i = 1, #bundled_code do
    table.insert(c_hex, string.format("0x%02x", string.byte(bundled_code, i)))
end
local c_payload = table.concat(c_hex, ", ")

print("⚙️  3. 正在锻造 C 语言物理外壳...")
local c_code = string.format([[
#include <stdio.h>
#include <stdlib.h>
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

// 物理封印的 L2C 编译器本体字节流
static const unsigned char l2c_payload[] = { %s, 0x00 };

int main(int argc, char** argv) {
    // 物理拉起 Lua 虚拟机
    lua_State *L = luaL_newstate();
    luaL_openlibs(L);

    // 🎯 核心桥接校准：对齐标准 Lua 的全局 arg 表
    // arg[-1] = 解释器(不填), arg[0] = 脚本/可执行文件本身, arg[1] = 第一个参数
    lua_newtable(L);
    for(int i = 0; i < argc; i++) {
        lua_pushstring(L, argv[i]);
        // C 语言的 argv[0] 对应 Lua 的 arg[0]
        // C 语言的 argv[1] 对应 Lua 的 arg[1]，以此类推
        lua_rawseti(L, -2, i); 
    }
    lua_setglobal(L, "arg");

    // 唤醒 L2C 编译器
    if (luaL_dostring(L, (const char*)l2c_payload) != LUA_OK) {
        fprintf(stderr, "❌ L2C 内核崩溃: %%s\n", lua_tostring(L, -1));
        lua_close(L);
        return 1;
    }

    lua_close(L);
    return 0;
}
]], c_payload)

local f_c = io.open("l2c_main.c", "w")
f_c:write(c_code)
f_c:close()

print("⚡ 4. 召唤 Clang/GCC 编译器进行终极封测...")

--  跨平台探针弹匣：涵盖 Mac 静态/动态，以及 Alpine(Musl) / Ubuntu(Glibc)
-- 🎯 跨平台探针弹匣：新增去除了 -flto 的终极降级方案，以及覆盖不同命名的 lua 链接参数
local compile_cmds = {
    -- 1. Mac Homebrew 极限静态/动态
    "clang -O3 -flto l2c_main.c /opt/homebrew/lib/liblua.a -o l2c_bin -I/opt/homebrew/include/lua -I/opt/homebrew/include 2>/dev/null",
    "clang -O3 -flto l2c_main.c -o l2c_bin -L/opt/homebrew/lib -I/opt/homebrew/include/lua -I/opt/homebrew/include -llua 2>/dev/null",
    
    -- 2. 🔥 Alpine Linux (Musl) 物理坐标级绝对静态封印！(追加 -static 彻底斩断 libc 依赖)
    "clang -O3 -flto l2c_main.c /usr/lib/lua5.4/liblua.a -o l2c_bin -I/usr/include/lua5.4 -I/usr/include/lua -static -lm 2>/dev/null",
    "gcc -O3 -flto l2c_main.c /usr/lib/lua5.4/liblua.a -o l2c_bin -I/usr/include/lua5.4 -I/usr/include/lua -static -lm 2>/dev/null", 

    -- 3. Alpine/Ubuntu Linux 传统静态封印
    "clang -O3 -flto l2c_main.c -o l2c_bin -I/usr/include/lua5.4 -I/usr/include/lua -static -llua5.4 -lm 2>/dev/null",
    "clang -O3 -flto l2c_main.c -o l2c_bin -I/usr/include/lua5.4 -I/usr/include/lua -static -llua -lm 2>/dev/null",
    
    -- 4. Alpine/Ubuntu 动态链接 (去除 -flto 防止 LTO 插件缺失报错！)
    "clang -O3 l2c_main.c -o l2c_bin -L/usr/lib/lua5.4 -I/usr/include/lua5.4 -I/usr/include/lua -llua -lm 2>/dev/null",
    "gcc -O3 l2c_main.c -o l2c_bin -L/usr/lib/lua5.4 -I/usr/include/lua5.4 -I/usr/include/lua -llua -lm 2>/dev/null"
}

local res = false
for _, cmd in ipairs(compile_cmds) do
    print("    探针射击: " .. cmd:gsub(" 2>/dev/null", ""))
    local status = os.execute(cmd)
    if status == 0 or status == true then
        res = true
        break
    end
end

if res then
    os.execute("rm l2c_main.c")
    print("\n 盗梦空间完美闭环！独立的 L2C 原生二进制已生成: ./l2c_bin")
    os.execute("ls -lh l2c_bin | awk '{print \" 物理体积: \" $5}'")
else
    print("❌ 编译失败。请尝试手动运行 Clang 并检查您的 Lua 头文件与链接库路径。")
end
