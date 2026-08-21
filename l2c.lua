-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- l2c.lua：L2C 终极项目级构建引擎 (Plugin Architecture)
local bundler = require("l2c_cli.bundler")
local builder = require("l2c_cli.builder")

-- ==============================================================================
-- L2C 神经链接接口：环境感知双轨调度器 (内存融合 vs 外部降级)
-- ==============================================================================
_G.L2C_Nelua_Run = function(args, redirect_out)
    -- 智能嗅探：我们是在单体二进制肚子里，还是在被普通 Lua 裸调？
    local is_standalone = (package.preload["nelua.runner"] ~= nil)

    if is_standalone then
        print(" [L2C 神经链接] 激活内置全内存 Nelua 引擎，零 I/O 极速转译...")
        local fs = require("nelua.utils.fs")
        if not fs._l2c_patched then
            fs._l2c_patched = true
            local old_isfile, old_readfile = fs.isfile, fs.readfile
            fs.isfile = function(path)
                for k, _ in pairs(_G.L2C_VFS or {}) do if path:sub(-#k) == k then return true end end
                return old_isfile(path)
            end
            fs.readfile = function(path)
                for k, v in pairs(_G.L2C_VFS or {}) do if path:sub(-#k) == k then return v end end
                return old_readfile(path)
            end
        end

        local runner = require("nelua.runner")
        -- 劫持输出流 (针对 Pico/ESP32 的 --print-code)
        if redirect_out then
            local captured = {}
            local function capture(...)
                for i = 1, select('#', ...) do
                    local v = select(i, ...)
                    if type(v) ~= "userdata" and type(v) ~= "table" then 
                        table.insert(captured, tostring(v)) 
                    end
                end
            end

            -- 终极劫持魔法：伪造一个完美的 FILE 对象！
            local fake_file = {
                -- 注意：(self, ...) 完美剥离了面向对象调用的 self 指针
                write = function(self, ...) capture(...); return self end,
                flush = function(self) return self end,
                close = function(self) return self end
            }

            -- 备份原始的物理流
            local old_write = io.write
            local old_stdout = io.stdout

            -- 偷梁换柱：只替换表层接口，绝不去触碰 C 内核的 io.output() 函数！
            io.write = capture
            io.stdout = fake_file
            
            local status = runner.run(args)
            
            -- 执行完毕，立刻把真实的物理流还给系统！
            io.write = old_write
            io.stdout = old_stdout
            
            if status == 0 then
                local f = io.open(redirect_out, "w")
                if f then f:write(table.concat(captured)); f:close() end
            end
            return status == 0
        else
            return runner.run(args) == 0
        end
    else
        -- =========================================================
        -- [降级模式] 检测到原生 Lua 环境，回退为 Shell 外部进程调用！
        -- =========================================================
        print(" [L2C 降级模式] 检测到原生 Lua 环境，回退为外部 Nelua 进程调用...")
        
        -- 安全拼装带空格的命令行参数
        local cmd_args = {}
        for _, v in ipairs(args) do
            if v:match("%s") then table.insert(cmd_args, "'" .. v .. "'")
            else table.insert(cmd_args, v) end
        end
        
        local cmd = "nelua " .. table.concat(cmd_args, " ")
        if redirect_out then cmd = cmd .. " > " .. redirect_out end
        
        local status = os.execute(cmd)
        return status == 0 or status == true
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
