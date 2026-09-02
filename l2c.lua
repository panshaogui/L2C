-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- 极客开关：取消注释即可开启全局覆盖率扫荡！
-- require("l2c_cli.profiler").start()

-- 挂载神经链接调度器
_G.L2C_Nelua_Run = require("l2c_cli.nelua_runner").execute

-- l2c.lua：L2C 终极项目级构建引擎 (Plugin Architecture)
local bundler = require("l2c_cli.bundler")
local builder = require("l2c_cli.builder")

-- [IDE 野路子]：无论后续编译是否报错，优先刷新 VSCode 智能提示！
pcall(function()
    require("l2c_cli.snippet_gen").generate("l2c.d.tl")
end)

local input_file = arg[1]
local output_bin = "native_app"
local target = "host"

if not input_file then
    print("L2C Compiler - 0-GC Native Compiler")
    print("用法: lua l2c.lua <入口文件.tl> [-o <输出>] [--target=pico|esp32|host]")
    os.exit(1)
end

for i = 2, #arg do
    if arg[i] == "-o" and arg[i+1] then output_bin = arg[i+1] end
    if arg[i]:match("^%-%-target=") then target = arg[i]:match("^%-%-target=(.+)") end
end

print(string.format(" [L2C] 启动构建，目标终端: %s，入口: %s", target:upper(), input_file))

-- 1. 组装与语法分析
local bundled_code, deps = bundler.bundle(input_file)
local tmp_file = builder.build_nelua(bundled_code, deps, input_file, output_bin)

-- 2. 靶向分发 (Target Dispatch)
if target == "pico" then
    require("l2c_cli.targets.pico").execute(tmp_file, output_bin, deps)
elseif target == "esp32" then
    require("l2c_cli.targets.esp32").execute(tmp_file, output_bin, deps)
else
    -- 默认 Host 模式：载入宿主机终极弹头，传递依赖包！
    require("l2c_cli.targets.host").execute(tmp_file, output_bin, deps)
end

-- 3. 打扫临时转译文件
os.execute("rm -f " .. tmp_file)
