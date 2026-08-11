-- ==============================================================================
-- L2C Unit Test: Bundler (物理拼接器与隐形债提取)
-- ==============================================================================
local bundler = require("l2c_cli.bundler")

-- [核心魔法]：劫持 VFS 虚拟文件系统，不读硬盘，直接在内存中测试！
_G.L2C_VFS = {
    ["main.tl"] = [[
-- @l2c_import: std/math.tl
-- @l2c_link: m
-- @l2c_include: math.h
local a = 1
]],
    ["std/math.tl"] = [[
local function math_add(a: integer, b: integer): integer return a + b end
]]
}

print("[UNIT] 正在测试 l2c_cli.bundler ...")

-- 静默 stdout 以防污染测试日志
local old_print = print
_G.print = function() end 
local code, deps = bundler.bundle("main.tl")
_G.print = old_print -- 恢复打印

--  战术断言开始
assert(code:match("local function math_add"), " VFS 导入 std/math.tl 失败！拼接正则出现退化！")
assert(code:match("local a = 1"), " 主文件内容在拼接后丢失！")
assert(code:match("local function L2C_Buffer"), " 核心魔法签证 <L2C_Intrinsics> 未能正确注入！")
assert(deps.ldflags:match("-lm"), " 隐形链接库 @l2c_link 提取失败！")
assert(deps.cincludes:match("<math.h>"), " C头文件 @l2c_include 提取失败！")

print(" bundler 虚拟合并与正则提取逻辑极其稳固！")
