-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- l2c.lua：L2C 终极项目级构建引擎 (Plugin Architecture)
local bundler = require("l2c_cli.bundler")
local builder = require("l2c_cli.builder")

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

print(string.format("🚀 [L2C] 启动构建，目标终端: %s，入口: %s", target:upper(), input_file))

-- 1. 组装与语法分析
local bundled_code, deps = bundler.bundle(input_file)
local tmp_file = builder.build_nelua(bundled_code, deps, input_file)

-- 2. 靶向分发 (Target Dispatch)
if target == "pico" then
    require("l2c_cli.targets.pico").execute(tmp_file, output_bin)
elseif target == "esp32" then
    require("l2c_cli.targets.esp32").execute(tmp_file, output_bin)
else
    -- 默认 Host 模式：载入宿主机终极弹头，传递依赖包！
    require("l2c_cli.targets.host").execute(tmp_file, output_bin, deps)
end

-- 3. 打扫临时转译文件
os.execute("rm -f " .. tmp_file)
