-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

local M = {}

-- 映射 1：Teal Record -> Nelua @record (带有类型感知的防御性注册表 + C FFI 探针)
function M:gen_local_type(node)
    --  [核心修复]：不要盲目信任 node.tk！
    -- 如果 node.name 存在，说明它是个正规的类型定义节点（如 local type xxx = record），优先从 name 里榨取真名
    local name = node.tk
    if node.name and node.name.tk then
        name = node.name.tk
    end
    
    -- 如果真名还是不幸撞上了关键字，直接紧急兜底
    if name == "local" or name == "type" then
        return "" 
    end

    --  [FFI 闭环]：精准捕获特殊命名空间 C 或 C_xxx，物理将 Teal 的声明转换为 Nelua FFI 绑定！
    if name == "C" or name:match("^C_") then
        local def = node.value and node.value.newtype and node.value.newtype.def
        if def and def.typeid then
            --  [防御性初始化白皮书]：如果还不存在就就地创建，绝对不触动老哥你原本的任何 registry
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
                        local t_name = arg.typename or "any"
                        if t_name == "string" then t_name = "cstring" end
                        
                        -- [内存降维]：Teal 里的 any，在 C 语言 FFI 里就是纯正的 void*（Nelua 叫 pointer）
                        if t_name == "any" then t_name = "pointer" end
                        
                        -- [核心修复]：如果是 nominal 自定义类型，拔出它藏在 names 数组里的真名！
                        if t_name == "nominal" and arg.names and arg.names[1] then
                            t_name = arg.names[1]
                        end
                        
                        table.insert(args_out, string.format("arg%d: %s", i, t_name))
                    end
                end
                
                local ret_type = "void"
                if func_info.rets and func_info.rets.tuple and func_info.rets.tuple[1] then
                    local ret_node = func_info.rets.tuple[1]
                    ret_type = ret_node.typename or "void"
                    if ret_type == "string" then ret_type = "cstring" end
                    
                    -- [内存降维]：返回值如果是 any，同样映射为 void* (pointer)
                    if ret_type == "any" then ret_type = "pointer" end
                    
                    -- [核心修复]：返回值同样剥离 nominal 伪装
                    if ret_type == "nominal" and ret_node.names and ret_node.names[1] then
                        ret_type = ret_node.names[1]
                    end
                end
                
                -- [核心架构统一]：生成绝对扁平的 C 函数映射！完美对接 expression.lua 中的裸调用！
                -- 示例生成：local function gpio_put(arg1: integer, arg2: integer): void <cimport('gpio_put'), nodecl> end
                local c_decl = string.format(
                    "local function %s(%s): %s <cimport('%s'), nodecl> end", 
                    func_name, 
                    table.concat(args_out, ", "), 
                    ret_type,
                    func_name
                )
                table.insert(out, c_decl)
            elseif func_info then
                -- [HLS FFI 补丁]：支持 C 全局变量 / 结构体实例的降维绑定！
                local v_type = func_info.typename or "any"
                if v_type == "string" then v_type = "cstring" end
                if v_type == "any" then v_type = "pointer" end
                
                if v_type == "nominal" and func_info.names and func_info.names[1] then
                    v_type = func_info.names[1]
                end
                
                local c_decl = string.format(
                    "local %s: %s <cimport('%s'), nodecl>", 
                    func_name, 
                    v_type, 
                    func_name
                )
                table.insert(out, c_decl)
            end
        end 

        return table.concat(out, "\n")
    end

    local def = node.value and node.value.newtype and node.value.newtype.def
    if not def or def.typename ~= "record" then return "" end
    
    self.record_registry = self.record_registry or {}
    
    --  [升级]：不仅保存字段名，还保存类型，用于后续的安全兜底初始化
    local fields_info = {}
    for _, field_name in ipairs(def.field_order or {}) do
        --  [精确对齐]：在这里同时拦截 _new 和所有类型为 "function" 的方法字段，彻底闭环
        local f_node = def.fields[field_name]
        if field_name ~= "_new" and f_node and f_node.typename ~= "function" then
            table.insert(fields_info, { 
                name = field_name, 
                type = def.fields[field_name].typename 
            })
        end
    end
    self.record_registry[name] = fields_info
    
    local out = {}
    if #fields_info == 0 then
        --  [FFI 物理降维]：如果发现这是一个空 Record，说明它是 C 语言的不透明指针占位符。
        -- 直接将其映射为底层 C 的 void* (Nelua 叫 @pointer)
        table.insert(out, string.format("local %s = @pointer", name))
    else
        table.insert(out, string.format("local %s = @record {", name))
        self.indent_level = self.indent_level + 1
        for _, f_info in ipairs(fields_info) do
            table.insert(out, self:indent() .. string.format("%s: %s,", f_info.name, f_info.type))
        end     
        self.indent_level = self.indent_level - 1
        table.insert(out, self:indent() .. "}")
    end
    
    return table.concat(out, "\n")
end

function M:gen_local_declaration(node)
    local var_name = node.vars[1].tk
    local exps_str = self:gen(node.exps)
    
    if type(exps_str) == "string" and exps_str:match("_tl_compat") then
        return "-- L2C: Stripped Teal _tl_compat polyfill"
    end
    
    --  [安全兜底] 如果没有赋值表达式，绝不生成带 "=" 的乱码
    if exps_str == "" then
        return string.format("local %s", var_name)
    else
        return string.format("local %s = %s", var_name, exps_str)
    end
    
end

-- 映射 2：函数声明（修复 UNKNOWN bug）
function M:gen_local_function(node)
    local name = node.name and node.name.tk or "anon"
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
                local t_name = arg.argtype and arg.argtype.typename or "any"
                if t_name == "nominal" and arg.argtype.names then 
                    t_name = arg.argtype.names[1] 
                end
                
                --  [核心修复]：把 []type 升级为安全的 span(type)
                if t_name == "array" and arg.argtype.elements then
                    local e_name = arg.argtype.elements.typename or "any"
                    if e_name == "nominal" and arg.argtype.elements.names then 
                        e_name = arg.argtype.elements.names[1] 
                    end
                    t_name = "span(" .. e_name .. ")"
                end

                --  [物理降维]：业务函数如果传 any，在底层就是 C 语言的不透明指针 void* (pointer)！
                if t_name == "any" then t_name = "pointer" end
                
                table.insert(args_list, arg.tk .. ": " .. t_name)
            end
        end
    end
    
    local args_str = table.concat(args_list, ", ")
    local header = string.format("local function %s(%s)", name, args_str)
    
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
                local t_name = arg.argtype and arg.argtype.typename or "any"
                if t_name == "nominal" and arg.argtype.names then 
                    t_name = arg.argtype.names[1] 
                end
                
                --  [降维打击：物理数组参数解包]
                if t_name == "array" and arg.argtype.elements then
                    local e_name = arg.argtype.elements.typename or "any"
                    if e_name == "nominal" and arg.argtype.elements.names then 
                        e_name = arg.argtype.elements.names[1] 
                    end
                    t_name = "span(" .. e_name .. ")"
                end

                --  [物理降维]：任何 any 参数都必须堕落为纯 C 指针
                if t_name == "any" then t_name = "pointer" end
                
                table.insert(args_list, arg.tk .. ": " .. t_name)
            end
        end
    end
    
    local args_str = table.concat(args_list, ", ")
    local header = string.format("global function %s(%s)", name, args_str)
    
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
                    local t_name = arg.argtype and arg.argtype.typename or "any"
                    if t_name == "nominal" and arg.argtype.names then 
                        t_name = arg.argtype.names[1] 
                    end
                    
                    -- [降维打击]：物理数组参数解包
                    if t_name == "array" and arg.argtype.elements then
                        local e_name = arg.argtype.elements.typename or "any"
                        if e_name == "nominal" and arg.argtype.elements.names then 
                            e_name = arg.argtype.elements.names[1] 
                        end
                        t_name = "span(" .. e_name .. ")"
                    end

                    -- [物理降维]：面向对象方法的 any 参数，必须堕落为纯 C 的 void* (pointer)！
                    if t_name == "any" then t_name = "pointer" end
                    
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