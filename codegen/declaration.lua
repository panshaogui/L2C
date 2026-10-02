-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

local M = {}
local IR = require("codegen.ir")

-- [核心架构升级] L2C-LIR 内部组装机：彻底告别散乱的字符串推导，组装严谨的物理内存模型
local function build_type_ir(type_node)
    if not type_node then return IR.Type.Pointer() end
    local t_name = type_node.typename or "any"
    
    -- 1. 剥离 nominal 伪装
    if t_name == "nominal" and type_node.names and type_node.names[1] then
        return IR.Type.Primitive(type_node.names[1])
    end
    
    -- 2. 物理数组降维 (递归组装 Span 树)
    if t_name == "array" and type_node.elements then
        local e_ir = build_type_ir(type_node.elements)
        return IR.Type.Span(e_ir)
    end
    
    -- 3. HFT 物理内存映射 (0-GC 强制转换)
    if t_name == "string" then return IR.Type.Primitive("cstring") end
    if t_name == "any" then return IR.Type.Pointer() end
    if t_name == "function" then return IR.Type.Function() end
    
    -- 兜底返回基础类型
    return IR.Type.Primitive(t_name)
end

-- 物理降维引擎垫片 (对老代码 100% 兼容无感)
local function lower_type(type_node)
    -- 第一步：拿到高度结构化的 IR 对象
    local ir_node = build_type_ir(type_node)
    -- 第二步：降维输出最终需要的底层代码
    return ir_node:to_nelua()
end

-- 映射 1：Teal Record -> Nelua @record (带有类型感知的防御性注册表 + C FFI 探针)
-- 【核心重构】：内部通用类型生成器，支持 local 和 global 动态注入！
function M:_gen_type_internal(node, scope_kwd)
    --  [核心修复]：不要盲目信任 node.tk！
    local name = node.tk
    if node.name and node.name.tk then
        name = node.name.tk
    end
    
    if node.names and node.names[1] then name = node.names[1].tk or node.names[1] end
    -- 如果真名还是不幸撞上了关键字，直接紧急兜底
    if name == "local" or name == "type" then
        return "" 
    end

    local function get_real_def(n)
        local d = n.type_def or n.value
        while d do
            if d.typename == "enum" or d.typename == "record" then return d end
            d = d.newtype or d.def
        end
        return nil
    end
    
    local def = get_real_def(node)

    --  [FFI 闭环]：精准捕获特殊命名空间 C 或 C_xxx
    if name == "C" or name:match("^C_") then
        local def = node.value and node.value.newtype and node.value.newtype.def
        if def and def.typeid then
            self.ffi_typeids = self.ffi_typeids or {}
            self.ffi_typeids[def.typeid] = true
        end
        
        if not def or def.typename ~= "record" then return "" end
        
        local out = {}
        for _, func_name in ipairs(def.field_order or {}) do
            local func_info = def.fields[func_name]
            if func_info and func_info.typename == "function" then
                local args_out = {}
                if func_info.args and func_info.args.tuple then
                    for i, arg in ipairs(func_info.args.tuple) do
                        local t_name = lower_type(arg)
                        table.insert(args_out, string.format("arg%d: %s", i, t_name))
                    end
                end
                
                local ret_type = "void"
                if func_info.rets and func_info.rets.tuple and func_info.rets.tuple[1] then
                    ret_type = lower_type(func_info.rets.tuple[1])
                end
                
                -- 【动态 Scope 注入】生成 local function 或 global function
                local c_decl = string.format(
                    "%s function %s(%s): %s <cimport('%s'), nodecl> end", 
                    scope_kwd,
                    func_name, 
                    table.concat(args_out, ", "), 
                    ret_type,
                    func_name
                )
                table.insert(out, c_decl)
            elseif func_info then
                -- 【动态 Scope 注入】全局变量/结构体实例绑定
                local v_type = lower_type(func_info)
                local c_decl = string.format(
                    "%s %s: %s <cimport('%s'), nodecl>", 
                    scope_kwd,
                    func_name, 
                    v_type, 
                    func_name
                )
                table.insert(out, c_decl)
            end
        end 

        return table.concat(out, "\n")
    end

    -- 终极真理解法：遍历 enumset 哈希表提取 Enum
    if def.typename == "enum" then
        local out = {}
        -- 【动态 Scope 注入】
        table.insert(out, string.format("%s %s = @enum {", scope_kwd, name))
        self.indent_level = self.indent_level + 1
        
        self.enum_registry = self.enum_registry or {}
        local val_idx = 0
        
        if def.enumset then
            local keys = {}
            for enum_key, _ in pairs(def.enumset) do
                if type(enum_key) == "string" then
                    table.insert(keys, enum_key)
                end
            end
            table.sort(keys)
            
            for _, enum_key in ipairs(keys) do
                table.insert(out, self:indent() .. string.format("%s = %d,", enum_key, val_idx))
                self.enum_registry[enum_key] = name
                val_idx = val_idx + 1
            end
        end
        
        self.indent_level = self.indent_level - 1
        table.insert(out, self:indent() .. "}")
        return table.concat(out, "\n")
    end

    if not def or def.typename ~= "record" then return "" end
    self.record_registry = self.record_registry or {}
    
    local fields_info = {}
    for _, field_name in ipairs(def.field_order or {}) do
        local f_node = def.fields[field_name]
        if field_name ~= "_new" and f_node and f_node.typename ~= "function" then
            local t_name = lower_type(f_node)
            table.insert(fields_info, { name = field_name, type = t_name })
        end
    end
    self.record_registry[name] = fields_info
    
    local out = {}
    if #fields_info == 0 then
        -- 【动态 Scope 注入】不透明指针
        table.insert(out, string.format("%s %s = @pointer", scope_kwd, name))
    else
        -- 【动态 Scope 注入】标准 Record
        if name:match("^Packed_") then
            table.insert(out, string.format("%s %s: type <packed> = @record {", scope_kwd, name))
        else
            table.insert(out, string.format("%s %s = @record {", scope_kwd, name))
        end
        
        self.indent_level = self.indent_level + 1
        for _, f_info in ipairs(fields_info) do
            table.insert(out, self:indent() .. string.format("%s: %s,", f_info.name, f_info.type))
        end     
        self.indent_level = self.indent_level - 1
        table.insert(out, self:indent() .. "}")
    end
    
    return table.concat(out, "\n")
end

-- ==========================================
-- 暴露出 Local 与 Global 两把双子星探针！
-- ==========================================
function M:gen_local_type(node)
    return self:_gen_type_internal(node, "local")
end

function M:gen_global_type(node)
    return self:_gen_type_internal(node, "global")
end

-- ==========================================
-- 内部通用变量声明引擎 (支持 local 和 global)
-- ==========================================
function M:_gen_var_declaration_internal(node, scope_kwd)
    local vars_list = {}
    
    -- 核心修复：遍历所有变量，智能提取变量名，彻底免疫带有类型的 nil 陷阱！
    if node.vars then
        for i, v_node in ipairs(node.vars) do
            local v_str = v_node.tk
            if not v_str and v_node[1] then
                v_str = type(v_node[1]) == "table" and v_node[1].tk or v_node[1]
            end
            
            -- 防弹衣：哪怕 Teal 真的吐出了 nil，我们也强制重命名，绝不引发底层语法错误
            if type(v_str) ~= "string" or v_str == "" or v_str == "nil" then
                v_str = "L2C_DUMMY_VAR_" .. tostring(math.random(1000, 9999))
            end
            
            table.insert(vars_list, v_str)
        end
    end
    
    local vars_str = table.concat(vars_list, ", ")
    if vars_str == "" then vars_str = "L2C_DUMMY_VAR_EMPTY" end
    
    local exps_str = self:gen(node.exps)
    
    if type(exps_str) == "string" and exps_str:match("_tl_compat") then
        return "-- L2C: Stripped Teal _tl_compat polyfill"
    end
    
    -- 完美支持多变量拼接并动态注入作用域 (local a, b = foo() 或 global a = 1)
    if not exps_str or exps_str == "" then
        return string.format("%s %s", scope_kwd, vars_str)
    else
        return string.format("%s %s = %s", scope_kwd, vars_str, exps_str)
    end
end

-- 暴露出 Local 与 Global 两把变量探针！
function M:gen_local_declaration(node)
    return self:_gen_var_declaration_internal(node, "local")
end

function M:gen_global_declaration(node)
    return self:_gen_var_declaration_internal(node, "global")
end


-- 映射 2：函数声明（修复 UNKNOWN bug）
function M:gen_local_function(node)
    local name = node.name and node.name.tk or "anon"
    -- 核心修复：拦截所有为 Teal 伪造的魔法原语，绝对禁止进入物理域形成遮蔽！
    local intrinsics = {
        L2C_Buffer=1, L2C_NumberArray=1, L2C_IntegerArray=1, L2C_RecordArray=1,
        L2C_Ref=1, L2C_Cast=1, L2C_FuncPtr=1, L2C_NewPointer=1, L2C_Tick_Reset=1,
        L2C_Static=1, L2C_Spinlock_Lock=1, L2C_Spinlock_Unlock=1, L2C_Memory_Barrier=1,
        L2C_PtrAsInt=1, L2C_NumberToInt=1, L2C_ReadArray=1, L2C_WriteArray=1,
        set=1, jmp=1, wait=1, in_=1, out=1, push=1, pull=1, mov=1, irq=1, wrap_target=1, wrap=1
    }
    if intrinsics[name] then
        return "-- [L2C 物理拦截] Stripped Intrinsic: " .. name
    end

    -- [HLS PIO 拦截网]：将软件函数降维为硬件状态机汇编
    if name:match("^L2C_PIO_") then
        local hls = require("codegen.hls_pio")
        self.pio_registry = self.pio_registry or {}
        local pio_name = name:gsub("^L2C_PIO_", "")
        self.pio_registry[pio_name] = hls.compile(node, self)
        -- 返回空注释，不向物理 C 宇宙发射任何代码
        return "-- [L2C HLS] PIO State Machine Synthesized: " .. pio_name
    end
    
    -- [HLS Verilog RTL 拦截网]：将软件逻辑强转为硅片数字电路
    if name:match("^L2C_HDL_") then
        local hls_v = require("codegen.hls_verilog")
        self.verilog_registry = self.verilog_registry or {}
        local mod_name = name:gsub("^L2C_HDL_", "")
        self.verilog_registry[mod_name] = hls_v.compile(node, self)
        return "-- [L2C HLS] Verilog RTL Synthesized: " .. mod_name
    end

    local args_list = {}
    if node.args and node.args[1] then
        for _, arg in ipairs(node.args) do
            if arg.kind == "argument" then
                -- [统一降维引擎] 彻底修复 string 穿透进 C 层的 GC 崩溃隐患
                local t_name = lower_type(arg.argtype)
                
                table.insert(args_list, arg.tk .. ": " .. t_name)
            end
        end
    end
    
    local args_str = table.concat(args_list, ", ")

    -- 核心修复：提取并翻译函数返回值类型 (支持多返回值)！
    local ret_list = {}
    if node.rets then
        for _, ret_node in ipairs(node.rets) do
            table.insert(ret_list, lower_type(ret_node))
        end
    end
    local ret_str = ""
    if #ret_list == 1 then ret_str = ": " .. ret_list[1]
    elseif #ret_list > 1 then ret_str = ": (" .. table.concat(ret_list, ", ") .. ")" end

    -- 拼接带返回值的函数头
    local header = string.format("local function %s(%s)%s", name, args_str, ret_str)
    
    self.indent_level = self.indent_level + 1
    local body = self:gen(node.body)
    self.indent_level = self.indent_level - 1
    
    return header .. "\n" .. body .. "\n" .. self:indent() .. "end"
end

--  [架构拓荒]：打通底层全局函数 (global function) 声明，用于导出 C 核心入口
function M:gen_global_function(node)
    local name = node.name and node.name.tk or "anon"
    local args_list = {}
    if node.args and node.args[1] then
        for _, arg in ipairs(node.args) do
            if arg.kind == "argument" then
                -- [统一降维引擎]
                local t_name = lower_type(arg.argtype)
                table.insert(args_list, arg.tk .. ": " .. t_name)
            end
        end
    end
    
    local args_str = table.concat(args_list, ", ")
    
    -- 核心修复：提取并翻译函数返回值类型 (支持多返回值)！
    local ret_list = {}
    if node.rets then
        for _, ret_node in ipairs(node.rets) do
            table.insert(ret_list, lower_type(ret_node))
        end
    end
    local ret_str = ""
    if #ret_list == 1 then ret_str = ": " .. ret_list[1]
    elseif #ret_list > 1 then ret_str = ": (" .. table.concat(ret_list, ", ") .. ")" end

    -- 拼接带返回值的函数头
    local header = string.format("global function %s(%s)%s", name, args_str, ret_str)
    
    self.indent_level = self.indent_level + 1
    local body = self:gen(node.body)
    self.indent_level = self.indent_level - 1
    
    return header .. "\n" .. body .. "\n" .. self:indent() .. "end"
end

--  [物理闭环]：精准捕获并转译 Teal 的 record_function 节点
function M:gen_record_function(node)
    local record_name = self:gen(node.fn_owner)
    local method_name = self:gen(node.name)
    
    local args_list = {}
    if node.args and node.args[1] then
        for _, arg in ipairs(node.args) do
            if arg.kind == "argument" then
                local tk = arg.tk
                -- [核心校准]：剥离 Teal 语法树中隐式注入的 self 参数
                if tk ~= "self" then
                    -- [统一降维引擎]
                    local t_name = lower_type(arg.argtype) 
                    table.insert(args_list, tk .. ": " .. t_name)
                end
            end
        end
    end
    
    local args_str = table.concat(args_list, ", ")
    
    self.indent_level = self.indent_level + 1
    local body = self:gen(node.body)
    self.indent_level = self.indent_level - 1
    
    -- 编织成标准的 Nelua 原生冒号类方法
    return string.format("function %s:%s(%s)\n%s\nend", record_name, method_name, args_str, body)
end

return M