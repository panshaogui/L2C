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

    -- 终极真理解法：遍历 enumset 哈希表提取 Enum
    if def.typename == "enum" then
        local out = {}
        table.insert(out, string.format("local %s = @enum {", name))
        self.indent_level = self.indent_level + 1
        
        self.enum_registry = self.enum_registry or {}
        local val_idx = 0
        
        -- 直接从 X光 照出的 enumset 里拿键名！
        if def.enumset then
            for enum_key, _ in pairs(def.enumset) do
                if type(enum_key) == "string" then
                    table.insert(out, self:indent() .. string.format("%s = %d,", enum_key, val_idx))
                    -- 写入注册表，供 literal.lua 拦截
                    self.enum_registry[enum_key] = name
                    val_idx = val_idx + 1
                end
            end
        end
        
        self.indent_level = self.indent_level - 1
        table.insert(out, self:indent() .. "}")
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
            -- 核心修复：取出类型名，并彻底剥离 nominal 伪装！
            local t_name = f_node.typename or "any"
            if t_name == "nominal" and f_node.names and f_node.names[1] then
                t_name = f_node.names[1]
            end
            
            -- 同步保持物理降维逻辑
            if t_name == "string" then t_name = "cstring" end
            if t_name == "any" then t_name = "pointer" end

            table.insert(fields_info, { 
                name = field_name, type = t_name 
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
        -- 确保 <packed> 放在 Nelua 要求的正确位置
        if name:match("^Packed_") then
            table.insert(out, string.format("local %s: type <packed> = @record {", name))
        else
            table.insert(out, string.format("local %s = @record {", name))
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

function M:gen_local_declaration(node)
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
    
    -- 完美支持多变量拼接 (local a, b = foo())
    if not exps_str or exps_str == "" then
        return string.format("local %s", vars_str)
    else
        return string.format("local %s = %s", vars_str, exps_str)
    end
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
                if t_name == "any" then 
                    t_name = "pointer"
                elseif t_name == "function" then
                    -- 完美对接 Nelua 的类型系统，保留函数特征！
                    t_name = "function()"
                end
                
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
                if t_name == "any" then 
                    t_name = "pointer" 
                elseif t_name == "function" then
                    -- 完美对接 Nelua 的类型系统，保留函数特征！
                    t_name = "function()"
                end
                
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
                    if t_name == "any" then 
                        t_name = "pointer" 
                    elseif t_name == "function" then
                        -- 完美对接 Nelua 的类型系统，保留函数特征！
                        t_name = "function()"
                    end
                    
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