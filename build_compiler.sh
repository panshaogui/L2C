#!/bin/bash
set -e

echo " [L2C Forge] 阶段 1：启动 VFS 矩阵打包..."
lua tools/pack_assets.lua

echo " [L2C Forge] 阶段 2：启动 GCC/Clang 熔炼超硬核单体二进制..."

# 提取所有的底层 C 基建源码 (排除自带 main 函数的 lua.c 和 luac.c)
LUA_SRC=$(ls clib/nelua_runtime/lua/*.c | grep -v "lua.c" | grep -v "luac.c")
LPEG_SRC=$(ls clib/nelua_runtime/lpeglabel/*.c)
SYS_SRC="clib/nelua_runtime/lfs.c clib/nelua_runtime/hasher.c clib/nelua_runtime/sys.c"

# 极限压榨，静态缝合！
gcc -O3 -flto \
    -Iclib/nelua_runtime/lua -Iclib/nelua_runtime/lpeglabel \
    clib/l2c_bootstrap.c $LUA_SRC $LPEG_SRC $SYS_SRC \
    -lm -ldl \
    -o l2c_bin

echo " [L2C Forge] 熔炼完成！终极主权二进制已生成：l2c_bin"
ls -lh l2c_bin
