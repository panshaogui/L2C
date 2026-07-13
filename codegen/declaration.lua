-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

local M = {}

-- 映射 1：Teal Record -> Nelua @record (带有类型感知的防御性注册表 + C FFI 探针)
function M:gen_local_type(node)
    -- 🎯 [核心修复]：不要盲目信任 node.tk！
    -- 如果 node.name 存在，说明它是个正规的类型定义节点（如 local type xxx = record），优先从 name 里榨取真名
    local name = node.tk
    if node.name and node.name.tk then
        name = node.name.tk
    end
    
    -- 如果真名还是不幸撞上了关键字，直接紧急兜底
    if name == "local" or name == "type" then
        return "" 
    end

    -- 🔥 [FFI 闭环]：精准捕获特殊命名空间 C 或 C_xxx，物理将 Teal 的声明转换为 Nelua FFI 绑定！
    if name == "C" or name:match("^C_") then
        local def = node.value and node.value.newtype and node.value.newtype.def
        if def and def.typeid then
            -- 🎯 [防御性初始化白皮书]：如果还不存在就就地创建，绝对不触动老哥你原本的任何 registry
            self.ffi_typeids = self.ffi_typeids or {}
            self.ffi_typeids[def.typeid] = true
        end
        
        if not def or def.typename ~= "record" then return "" end
        
        local out = {}
        -- 🛡️ [防连环雷]：确保在多文件物理拼接时，只生成一次 c 记录的全局外壳！
        if not self.c_namespace_emitted then
            table.insert(out, "global c = @record{}")
            self.c_namespace_emitted = true
        end

        for _, func_name in ipairs(def.field_order or {}) do
            local func_info = def.fields[func_name]
            if func_info and func_info.typename == "function" then
                local args_out = {}
                if func_info.args and func_info.args.tuple then
                    for i, arg in ipairs(func_info.args.tuple) do
                        local t_name = arg.typename or "any"
                        if t_name == "string" then t_name = "cstring" end
                        
                        -- ⚡ [内存降维]：Teal 里的 any，在 C 语言 FFI 里就是纯正的 void*（Nelua 叫 pointer）
                        if t_name == "any" then t_name = "pointer" end
                        
                        -- ⚡ [核心修复]：如果是 nominal 自定义类型，拔出它藏在 names 数组里的真名！
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
                    
                    -- ⚡ [内存降维]：返回值如果是 any，同样映射为 void* (pointer)
                    if ret_type == "any" then ret_type = "pointer" end
                    
                    -- ⚡ [核心修复]：返回值同样剥离 nominal 伪装
                    if ret_type == "nominal" and ret_node.names and ret_node.names[1] then
                        ret_type = ret_node.names[1]
                    end
                end
                
                -- ⚡ [终极保障]：注入 cimport('%s') 锁定 C 原生符号
                local c_decl = string.format(
                    "function c.%s(%s): %s <cimport('%s'), nodecl> end", 
                    func_name, 
                    table.concat(args_out, ", "), 
                    ret_type,
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
    
    -- 🔥 [升级]：不仅保存字段名，还保存类型，用于后续的安全兜底初始化
    local fields_info = {}
    for _, field_name in ipairs(def.field_order or {}) do
        -- 🎯 [精确对齐]：在这里同时拦截 _new 和所有类型为 "function" 的方法字段，彻底闭环
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
        -- 🎯 [FFI 物理降维]：如果发现这是一个空 Record，说明它是 C 语言的不透明指针占位符。
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
    
    local exp = node.exps and node.exps[1]
    if exp and exp.kind == "op" and exp.op.op == "@funcall" then
        -- 宏 1：字节缓冲
        if exp.e1.tk == "L2C_Buffer" then
            local size = self:gen(exp.e2[1])
            return string.format("local %s: [%s]byte", var_name, size)
        end
        -- 🔥 宏 2：强类型定长数字栈数组
        if exp.e1.tk == "L2C_NumberArray" then
            local size = self:gen(exp.e2[1])
            return string.format("local %s: [%s]number", var_name, size)
        end
        -- 🔥 宏 3：强类型定长整数栈数组
        if exp.e1.tk == "L2C_IntegerArray" then
            local size = self:gen(exp.e2[1])
            return string.format("local %s: [%s]integer", var_name, size)
        end
        -- 🔥 [OOP 魔法宏]：拦截 Type._ptr()，在 C 栈上强制声明未初始化的 void* 物理指针！
        local fnode = exp.e1
        if fnode.kind == "op" and fnode.op.op == "." and fnode.e2.tk == "_ptr" then
            return string.format("local %s: pointer", var_name)
        end
    end
    
    -- 🛡️ [安全兜底] 如果没有赋值表达式，绝不生成带 "=" 的乱码
    if exps_str == "" then
        return string.format("local %s", var_name)
    else
        return string.format("local %s = %s", var_name, exps_str)
    end
    
    -- return string.format("local %s = %s", var_name, exps_str)
end

-- 映射 2：函数声明（修复 UNKNOWN bug）
function M:gen_local_function(node)
    local name = node.name and node.name.tk or "anon"
    local args_list = {}
    if node.args and node.args[1] then
        for _, arg in ipairs(node.args) do
            if arg.kind == "argument" then
                local t_name = arg.argtype and arg.argtype.typename or "any"
                if t_name == "nominal" and arg.argtype.names then 
                    t_name = arg.argtype.names[1] 
                end
                
                -- 🔥 [核心修复]：把 []type 升级为安全的 span(type)
                if t_name == "array" and arg.argtype.elements then
                    local e_name = arg.argtype.elements.typename or "any"
                    if e_name == "nominal" and arg.argtype.elements.names then 
                        e_name = arg.argtype.elements.names[1] 
                    end
                    t_name = "span(" .. e_name .. ")"
                end

                -- 🔥 [物理降维]：业务函数如果传 any，在底层就是 C 语言的不透明指针 void* (pointer)！
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

-- 🔥 [架构拓荒]：打通底层全局函数 (global function) 声明，用于导出 C 核心入口
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
                
                -- 🔥 [降维打击：物理数组参数解包]
                if t_name == "array" and arg.argtype.elements then
                    local e_name = arg.argtype.elements.typename or "any"
                    if e_name == "nominal" and arg.argtype.elements.names then 
                        e_name = arg.argtype.elements.names[1] 
                    end
                    t_name = "span(" .. e_name .. ")"
                end

                -- 🔥 [物理降维]：任何 any 参数都必须堕落为纯 C 指针
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

-- 🔥 [物理闭环]：精准捕获并转译 Teal 的 record_function 节点
function M:gen_record_function(node)
    local record_name = self:gen(node.fn_owner)
    local method_name = self:gen(node.name)
    
    local args = self:gen(node.args)
    local body = self:gen(node.body)
    
    -- 🔥 [核心校准]：Teal 的方法参数体里带着显式的 "self, "，而 Nelua 的冒号语法糖会自动注入 self。
    -- 我们在这里把多余的 self 声明剔除掉，防止 Nelua 推断出 any 从而崩溃。
    args = args:gsub("^self%s*,%s*", "") -- 擦除开头的 "self, "
    args = args:gsub("^self$", "")       -- 如果只有单参数 self，直接擦干
    
    -- 编织成标准的 Nelua 原生冒号类方法
    return string.format("function %s:%s(%s)\n%s\nend", record_name, method_name, args, body)
end

return M
