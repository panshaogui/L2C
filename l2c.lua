-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- l2c.lua：L2C 终极项目级构建引擎 (Plugin Architecture)
local bundler = require("l2c_cli.bundler")
local builder = require("l2c_cli.builder")

-- ==============================================================================
-- L2C 神经链接接口：全内存接管 Nelua 引擎与 VFS 文件系统劫持
-- ==============================================================================
_G.L2C_Nelua_Run = function(args, redirect_out)
    print(" [L2C 神经链接] 激活内置全内存 Nelua 引擎，零 I/O 极速转译...")
    
    -- 1. 物理挂载 VFS：欺骗 Nelua，让它从二进制内存常量区读取系统标准库！
    local fs = require("nelua.utils.fs")
    if not fs._l2c_patched then
        fs._l2c_patched = true
        local old_isfile, old_readfile = fs.isfile, fs.readfile
        fs.isfile = function(path)
            for k, _ in pairs(_G.L2C_VFS or {}) do
                if path:sub(-#k) == k then return true end
            end
            return old_isfile(path)
        end
        fs.readfile = function(path)
            for k, v in pairs(_G.L2C_VFS or {}) do
                if path:sub(-#k) == k then return v end
            end
            return old_readfile(path)
        end
    end

    local runner = require("nelua.runner")
    
    -- 2. 劫持输出流 (针对 Pico/ESP32 的 --print-code)
    if redirect_out then
        local captured = {}
        local old_write, old_stdout_write = io.write, io.stdout.write
        local function capture(...)
            for i = 1, select('#', ...) do
                local v = select(i, ...)
                if type(v) ~= "userdata" then table.insert(captured, tostring(v)) end
            end
        end
        io.write, io.stdout.write = capture, capture
        
        -- 核心修复：Nelua 的入口叫 run，不叫 main！
        local status = runner.run(args)
        
        io.write, io.stdout.write = old_write, old_stdout_write
        
        if status == 0 then
            local f = io.open(redirect_out, "w")
            if f then f:write(table.concat(captured)); f:close() end
        end
        return status == 0
    else
        -- 3. 核心修复：直接全内存调用 (针对 Host 生成二进制)
        return runner.run(args) == 0
    end
end

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
