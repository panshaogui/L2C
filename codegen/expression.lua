-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

local M = {}

function M:gen_op(node)
    local op_sym = node.op.op
    --  [语法兼容]：强制抹平 Teal 和 Nelua 对“不等于”符号的解析差异
    if op_sym == "!=" then op_sym = "~=" end

    if op_sym == "@funcall" then
        local func_node = node.e1

        --  [硬核手术一：多核内存熔断机制]
        if func_node.kind == "variable" and func_node.tk == "L2C_Tick_Reset" then
            return "L2C_Get_Arena():deallocall()"
        end

        --  [C FFI 内存宏]：取地址符（对应 C 语言的 &指针传入）
        if func_node.kind == "variable" and func_node.tk == "L2C_Ref" then
            return "&(" .. self:gen(node.e2[1]) .. ")"
        end

        --  [C FFI 内存宏]：原生强转 (Primitive Cast，专治 cstring 等基础类型)
        if func_node.kind == "variable" and func_node.tk == "L2C_Cast" then
            local ptr_exp = self:gen(node.e2[1])
            local type_node = node.e2[2]
            local type_name = type_node.value or type_node.tk or "any"
            if type_name:match('^".*"$') or type_name:match("^'.*'$") then
                type_name = type_name:sub(2, -2)
            end
            -- Nelua 原生直接强转语法：(@Type)(ptr)
            return string.format("(@%s)(%s)", type_name, ptr_exp)
        end
        
        -- [C FFI 内存宏]：C 语言回调函数指针强转！
        if func_node.kind == "variable" and func_node.tk == "L2C_FuncPtr" then
            return "(@pointer)(" .. self:gen(node.e2[1]) .. ")"
        end

        -- 物理指针整数化，碾压类型检查
        if func_node.kind == "variable" and func_node.tk == "L2C_PtrAsInt" then
            return "(@integer)((@usize)(" .. self:gen(node.e2[1]) .. "))"
        end

        -- [C FFI 内存宏]：静态持久化内存分配 (L2C_Static)
        if func_node.kind == "variable" and func_node.tk == "L2C_Static" then
            local type_node = node.e2[1]
            -- 兼容传入字符或者直接传入类型名
            local type_name = type_node.value or type_node.tk or "any"
            if type_name:match('^".*"$') or type_name:match("^'.*'$") then
                type_name = type_name:sub(2, -2)
            end
            
            -- 在 Nelua 中使用 <static> 注解，强制将其放在 C 语言的 .bss 数据段！
            return string.format([[(do
                local o_static: %s <static>
                in &o_static
                end)]], type_name)
        end

        --  [C FFI 内存宏]：零拷贝强转（Zero-Copy Cast 优雅 OOP 版）
        if func_node.kind == "op" and func_node.op.op == "." and func_node.e2.tk == "_cast" then
            local type_name = func_node.e1.tk
            local ptr_exp = self:gen(node.e2[1])
            -- Nelua 原生纯 C 物理指针强转语法：(@*Type)(ptr)
            return string.format("(@*%s)(%s)", type_name, ptr_exp)
        end

        --[[  [前提二：物理级自旋锁 API 映射]

        if func_node.kind == "variable" and func_node.tk == "L2C_Spinlock_Lock" then
            return "L2C_SPINLOCK_LOCK(" .. self:gen(node.e2[1]) .. ")"
        end
        if func_node.kind == "variable" and func_node.tk == "L2C_Spinlock_Unlock" then
            return "L2C_SPINLOCK_UNLOCK(" .. self:gen(node.e2[1]) .. ")"
        end

        if func_node.kind == "variable" and func_node.tk == "L2C_Memory_Barrier" then
            return "l2c_memory_barrier()"
        end

        --]]
  
        --  [硬核手术二：防御性内联展开]
        if func_node.kind == "op" and func_node.op.op == "." and func_node.e2.tk == "_new" then
            local type_name = func_node.e1.tk
            local fields = self.record_registry[type_name] or {}
            
            local kv_pairs = {}
            local param_index = 1
   
            for _, f_info in ipairs(fields) do
                local arg_node = node.e2[param_index]
                local arg_val
                
                if arg_node then
                    -- 如果高层传了参数，直接翻译
                    arg_val = self:gen(arg_node)
                    param_index = param_index + 1
                else
                    --  [安全兜底] 如果高层少传了参数，根据强类型自动补齐默认值！防止 C 脏内存！
                    if f_info.type == "integer" or f_info.type == "number" then
                        arg_val = "0"
                    elseif f_info.type == "boolean" then
                        arg_val = "false"
                    else
                        arg_val = "nilptr"
                    end
                end 
                
                table.insert(kv_pairs, string.format("o_ptr.%s = %s", f_info.name, arg_val))
            end
            local body_str = table.concat(kv_pairs, "\n  ")
            
            -- 使用内联路由函数进行物理指针展开
            return string.format([[(do
                local o_ptr = L2C_Get_Arena():new(@%s)
                %s
                in o_ptr
                end)]], type_name, body_str)
        end

        -- 普通函数调用兜底
        return self:gen(node.e1) .. "(" .. self:gen(node.e2) .. ")"

    elseif op_sym == "." then
        --   [正规军闭环]：在这里拦截点号点访问！
        -- 递归调用 self:gen(node.e1)，如果左节点是大写 C 的变量，它会被我们的 gen_variable 拦截成小写 "c"
        local left = self:gen(node.e1)
        local right = self:gen(node.e2)
        
        return left .. "." .. right

    end

    --   [正规军底层闭环]：拦截 Lua 的字符串连接符，规避 Nelua 的强类型编译崩溃
    if op_sym == ".." then
        -- 在 Nelua 世界中，如果用于 print 打印，直接转换成多参数（用逗号隔开）
        -- 比如 "count=" .. count  =>  "count=", count
        return self:gen(node.e1) .. ", " .. self:gen(node.e2)
    elseif op_sym == "==" then op_sym = "=="

    end

    if op_sym == "@index" then
        --   1-based (Teal) 到 0-based (Nelua/C) 的平移，逻辑完美
        return self:gen(node.e1) .. "[" .. self:gen(node.e2) .. " - 1]"
    else
        --   [位运算与一元操作护甲]：如果发现 e2 是空的，说明这是一个一元操作符 (如 ~a, -a, not a)
        if node.e2 == nil then
            --   唯独在这里加了一个空格 " "，彻底防止 not a 粘连变成 nota
            return op_sym .. " " .. self:gen(node.e1)
        end
        
        -- 正常的二元操作符兜底 (涵盖了 +, -, *, /, &, |, <<, >> 等所有符号！)
        return self:gen(node.e1) .. " " .. op_sym .. " " .. self:gen(node.e2)
    end
end

-- ------------------------------------------
--  映射 6：变量重新赋值 (Assignment)
-- ------------------------------------------
function M:gen_assignment(node)
    -- Teal AST 中，赋值语句的左边叫 vars，右边叫 exps
    local vars_str = self:gen(node.vars)
    local exps_str = self:gen(node.exps)
    return vars_str .. " = " .. exps_str
end

--  [物理闭环]：转译括号表达式节点
function M:gen_paren(node)
    -- node[1] 或 node.e1 通常代表括号内部的表达式，直接递归翻译并包上小括号
    return string.format("(%s)", self:gen(node[1] or node.e1))
end

function M:gen_index(node)
    -- 彻底回归你的原始正确基线
    return self:gen(node.e1) .. "." .. self:gen(node.e2)
end

return M
