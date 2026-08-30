// ==============================================================================
// Copyright (c) 2026 Panshaogui | MIT License
// L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
// ==============================================================================

// ==============================================================================
// L2C Bootloader: The Core VM Ignition
// ==============================================================================
#include <stdio.h>
#include <stdlib.h>
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

// 声明外部 C 扩展的注册入口
int luaopen_lpeglabel(lua_State *L);
int luaopen_lfs(lua_State *L);
int luaopen_sys(lua_State *L);
int luaopen_hasher(lua_State *L);

// 挂载我们刚才生成的全内存 VFS 矩阵！
#include "l2c_bundle.h"

int main(int argc, char **argv) {
    // 1. 点燃 0-GC 编译器内核 (Lua 5.4 VM)
    lua_State *L = luaL_newstate();
    luaL_openlibs(L);

    // 2. 物理挂载 C 语言扩展，从此告别 lpeg.so 找不到的悲剧！
    luaL_requiref(L, "lpeglabel", luaopen_lpeglabel, 1); lua_pop(L, 1);
    luaL_requiref(L, "lfs", luaopen_lfs, 1); lua_pop(L, 1);
    luaL_requiref(L, "sys", luaopen_sys, 1); lua_pop(L, 1);
    luaL_requiref(L, "hasher", luaopen_hasher, 1); lua_pop(L, 1);

    // 3. 伪装系统参数表 arg
    lua_createtable(L, argc, 0);
    for (int i = 0; i < argc; i++) {
        lua_pushstring(L, argv[i]);
        lua_rawseti(L, -2, i);
    }
    lua_setglobal(L, "arg");

    // 4. 将几十兆的 Lua 源码瞬间注入内存！
    l2c_preload_assets(L);

    // 5. 跨维启动！执行主脚本 l2c.lua
    if (luaL_dostring(L, "require('l2c')") != LUA_OK) {
        fprintf(stderr, " [L2C Core Panic] %s\n", lua_tostring(L, -1));
        lua_close(L);
        return 1;
    }

    lua_close(L);
    return 0;
}
