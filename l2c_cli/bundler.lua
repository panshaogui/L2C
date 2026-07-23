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
    local function read_and_bundle(file_path, bundled)
        bundled = bundled or {}
        if bundled[file_path] then return "" end
        bundled[file_path] = true
        local f = io.open(file_path, "r")
        if not f then print("找不到导入文件: " .. file_path) os.exit(1) end
        local code = f:read("*a")
        f:close()
        code = code:gsub("%-%-%s*@l2c_import:%s*([%w_%.%-%/]+)", function(import_file)
            print("物理展开合并: " .. import_file)
            return "\n-- IMPORT START: " .. import_file .. " --\n" .. read_and_bundle(import_file, bundled) .. "\n-- IMPORT END --\n"
        end)
        return code
    end

    local bundled_code = read_and_bundle(input_file)
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
        
    ]]

    bundled_code = l2c_core_headers .. bundled_code

    local deps = { ldflags = "", cincludes = "", cpp_sources = {} }
    for lib in bundled_code:gmatch("%-%-%s*@l2c_link:%s*([%w_%-]+)") do deps.ldflags = deps.ldflags .. " -l" .. lib end
    for header in bundled_code:gmatch("%-%-%s*@l2c_include:%s*([%w_%.%-%/]+)") do deps.cincludes = deps.cincludes .. "## cinclude '<" .. header .. ">'\n" end
    for src in bundled_code:gmatch("%-%-%s*@l2c_source:%s*([%w_%.%-%/]+)") do table.insert(deps.cpp_sources, src) end

    return bundled_code, deps
end
return M
