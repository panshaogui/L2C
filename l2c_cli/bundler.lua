-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

local M = {}
-- L2C 隐形债务账本
M.STD_DEBT = {
    ["std/zmq.tl"] = { ldflags = " -lc++ -lsodium", cflags  = "" },
    ["std/simdjson.tl"] = { ldflags = " -lc++", cflags  = "" }
}

function M.bundle(input_file)
    local bundled_lines = {}
    local line_map = {}
    local bundled_set = {}

    -- 辅助函数：逐行装配并记录映射
    local function add_line(text, file_name, orig_line)
        table.insert(bundled_lines, text)
        line_map[#bundled_lines] = { file = file_name, line = orig_line }
    end

    local l2c_core_headers = [[ 
        -- L2C Core Intrinsics
        local function L2C_Buffer(size: integer): any end
        local function L2C_NumberArray(size: integer): {number} end
        local function L2C_IntegerArray(size: integer): {integer} end
        local function L2C_Ref(var: any): any end
        local function L2C_Cast(ptr: any, tname: string): any end
        local function L2C_FuncPtr(func: any): any end
        local function L2C_NewPointer(): any end
        local function L2C_Tick_Reset() end
        local function L2C_Static(type_name: any): any end
        local function L2C_Spinlock_Lock(lock_id: integer) end
        local function L2C_Spinlock_Unlock(lock_id: integer) end
        local function L2C_Memory_Barrier() end
        local function L2C_PtrAsInt(ptr: any): integer end
        local function L2C_NumberToInt(n: number): integer end
        local function L2C_ReadArray(arr_ptr: integer, idx: integer): integer end
        local function L2C_WriteArray(arr_ptr: integer, idx: integer, val: integer) end
        -- [L2C HLS RTL Intrinsics 硬件寄存器签证]
        local function HDL_Reg(init_val: integer): integer end
        -- [L2C HLS PIO Intrinsics 硬件状态机魔法签证]
        local function set(a: any, b?: any) end
        local function jmp(a: any, b?: any) end
        local function wait(a: any, b?: any, c?: any) end
        local function in_(a: any, b?: any) end
        local function out(a: any, b?: any) end
        local function push(a?: any, b?: any) end
        local function pull(a?: any, b?: any) end
        local function mov(a: any, b?: any) end
        local function irq(a: any, b?: any) end
        local function wrap_target() end
        local function wrap() end
        
    ]]

    -- 1. 注入内建宏，标记其来自 <L2C_Intrinsics>
    for line in l2c_core_headers:gmatch("([^\n]*)\n?") do
        if line ~= "" then add_line(line, "<L2C_Intrinsics>", 0) end
    end

    -- 2. 逐行递归装配文件
    local function read_and_bundle(file_path)
        if bundled_set[file_path] then return end
        bundled_set[file_path] = true
        
        local content = ""
        -- [VFS 拦截]：优先从全局虚拟内存文件系统中读取！
        if _G.L2C_VFS and _G.L2C_VFS[file_path] then
            content = _G.L2C_VFS[file_path]
            print(" 内存 VFS 展开合并: " .. file_path)
        else
            -- VFS 里没有（比如用户写的本地业务文件），再降级去读硬盘
            local f = io.open(file_path, "r")
            if not f then print(" 致命错误: 找不到导入文件: " .. file_path) os.exit(1) end
            content = f:read("*a")
            f:close()
            print(" 物理硬盘展开合并: " .. file_path)
        end
        
        local orig_line = 1
        -- 确保末尾有换行符，防正则漏掉最后一行
        if content:sub(-1) ~= "\n" then content = content .. "\n" end
        
        -- 核心魔法：用正则模拟 f:lines()，完美兼容 Windows(\r\n) 和 Unix(\n) 换行！
        for line in content:gmatch("([^\r\n]*)\r?\n") do
            -- [L2C IDE 隐身衣]：遇到给 VSCode 看的类型声明库，直接在物理域抹除！
            if line:match('require%s*%(?%s*["\']l2c%.d["\']%s*%)?') then
                -- Do nothing (相当于跳过)
            else
                local import_file = line:match("%-%-%s*@l2c_import:%s*([%w_%.%-%/]+)")
                if import_file then
                    add_line("-- IMPORT START: " .. import_file .. " --", file_path, orig_line)
                    read_and_bundle(import_file)
                    add_line("-- IMPORT END --", file_path, orig_line)
                else
                    add_line(line, file_path, orig_line)
                end
            end
            orig_line = orig_line + 1
        end
    end

    read_and_bundle(input_file)
    local bundled_code = table.concat(bundled_lines, "\n")

    local deps = { ldflags = "", cincludes = "", cpp_sources = {}, line_map = line_map }
    for lib in bundled_code:gmatch("%-%-%s*@l2c_link:%s*([%w_%-]+)") do deps.ldflags = deps.ldflags .. " -l" .. lib end
    for header in bundled_code:gmatch("%-%-%s*@l2c_include:%s*([%w_%.%-%/]+)") do deps.cincludes = deps.cincludes .. "## cinclude '<" .. header .. ">'\n" end
    for src in bundled_code:gmatch("%-%-%s*@l2c_source:%s*([%w_%.%-%/]+)") do table.insert(deps.cpp_sources, src) end

    return bundled_code, deps
end
return M
