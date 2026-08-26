-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

local M = {}
local IR = require("codegen.ir")

-- [L2C-LIR 桥接引擎]：将 Teal 传入的字符串类型标识符解析为强类型 IR，彻底免疫泛型漏水
local function parse_type_to_ir(type_node)
    local type_name = type_node.value or type_node.tk or "any"
    
    -- 智能脱壳：扒去 Teal 字符串的单/双引号
    if type_name:match('^".*"$') or type_name:match("^'.*'$") then
        type_name = type_name:sub(2, -2)
    end
    
    -- IR 物理坍缩：0-GC 映射
    if type_name == "string" then return IR.Type.Primitive("cstring") end
    if type_name == "any" then return IR.Type.Pointer() end
    if type_name == "function" then return IR.Type.Function() end
    
    -- IR 数组坍缩：将 "[]integer" 动态切片类型转为严谨的 Span IR
    local arr_elem = type_name:match("^%[%](.+)$")
    if arr_elem then
        return IR.Type.Span(IR.Type.Primitive(arr_elem))
    end
    
    -- 兜底
    return IR.Type.Primitive(type_name)
end

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
            -- [接入 IR 引擎]
            local type_ir = parse_type_to_ir(node.e2[2])
            
            -- Nelua 原生直接强转语法：(@Type)(ptr)
            return string.format("(@%s)(%s)", type_ir:to_nelua(), ptr_exp)
        end
        
        -- [C FFI 内存宏]：C 语言回调函数指针强转！
        if func_node.kind == "variable" and func_node.tk == "L2C_FuncPtr" then
            return "(@pointer)(" .. self:gen(node.e2[1]) .. ")"
        end

        -- 物理指针整数化，碾压类型检查
        if func_node.kind == "variable" and func_node.tk == "L2C_PtrAsInt" then
            return "(@integer)((@usize)(" .. self:gen(node.e2[1]) .. "))"
        end

        -- [类型碾压] 将浮点数强制转为系统等宽整数
        if func_node.kind == "variable" and func_node.tk == "L2C_NumberToInt" then
            return "(@integer)(" .. self:gen(node.e2[1]) .. ")"
        end

        -- [物理切片器] 直接映射为兵工厂里的 C 语言原生内联数组指针读写
        if func_node.kind == "variable" and func_node.tk == "L2C_ReadArray" then
            return "l2c_spsc_read_arr(" .. self:gen(node.e2) .. ")"
        end
        
        if func_node.kind == "variable" and func_node.tk == "L2C_WriteArray" then
            return "l2c_spsc_write_arr(" .. self:gen(node.e2) .. ")"
        end

        -- [0-GC 物理栈内存] 强制展开为 C 语言 VLA 定长栈数组！绝对安全，离开作用域瞬间释放！
        if func_node.kind == "variable" and func_node.tk == "L2C_Buffer" then
            return "(@[" .. self:gen(node.e2[1]) .. "]byte)()"
        end

        if func_node.kind == "variable" and func_node.tk == "L2C_IntegerArray" then
            return "(@[" .. self:gen(node.e2[1]) .. "]integer)()"
        end

        if func_node.kind == "variable" and func_node.tk == "L2C_NumberArray" then
            return "(@[" .. self:gen(node.e2[1]) .. "]number)()"
        end

        -- 终极物理连片内存：在 Tick 竞技场开辟绝对连续的结构体数组！
        if func_node.kind == "variable" and func_node.tk == "L2C_RecordArray" then
            -- [接入 IR 引擎]
            local type_ir = parse_type_to_ir(node.e2[1])
            local size_expr = self:gen(node.e2[2])
            local type_name = type_ir:to_nelua()
            
            -- Nelua 语法降维：利用 Arena 瞬间划拨总字节数 (数量 * sizeof(类型))
            -- 并暴力强转为 C 语言的 0 长度指针数组！
            return string.format("(@*[0]%s)(L2C_Get_Arena():alloc(%s * #@%s))", type_name, size_expr, type_name)
        end

        -- [C FFI 内存宏]：静态持久化内存分配 (L2C_Static)
        if func_node.kind == "variable" and func_node.tk == "L2C_Static" then
            -- [接入 IR 引擎]
            local type_ir = parse_type_to_ir(node.e2[1])
            
            -- 在 Nelua 中使用 <static> 注解，强制将其放在 C 语言的 .bss 数据段！
            return string.format([[(do
                local o_static: %s <static>
                in &o_static
                end)]], type_ir:to_nelua())
        end

        --  [C FFI 内存宏]：零拷贝强转（Zero-Copy Cast 优雅 OOP 版）
        if func_node.kind == "op" and func_node.op.op == "." and func_node.e2.tk == "_cast" then
            local type_name = func_node.e1.tk
            local ptr_exp = self:gen(node.e2[1])
            -- Nelua 原生纯 C 物理指针强转语法：(@*Type)(ptr)
            return string.format("(@*%s)(%s)", type_name, ptr_exp)
        end

        -- 核心新增：数组形态的 0-GC 强转魔法签证！
        -- 将 Teal 的 any 完美降维成 Nelua 的 (@*[0]Type) C 语言数组指针！
        if func_node.kind == "op" and func_node.op.op == "." and func_node.e2.tk == "_cast_arr" then
            local type_name = func_node.e1.tk
            local ptr_exp = self:gen(node.e2[1])
            return string.format("(@*[0]%s)(%s)", type_name, ptr_exp)
        end

        if func_node.kind == "op" and func_node.op.op == "." and func_node.e2.tk == "_ptr" then
            return "nilptr"
        end

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
        local left = self:gen(node.e1)
        local right = self:gen(node.e2)
        
        -- [L2C 深度语义熔断]：封杀动态字符串库
        if left == "string" then
            self:panic("E005", node)
        end

        -- [C FFI 降维打击]：自动将 C_XXX.func 转换为 C 语言的原生全局 func()！
        -- 这让我们在 Teal 里享受 OOP 提示，在 C 里享受零开销全局内联！
        if left == "C" or left:match("^C_") then
            return right
        end

        return left .. "." .. right

    end

    -- [L2C 深度语义熔断]：封杀 Lua 的字符串连接符，彻底断绝隐式内存分配
    if op_sym == ".." then
        self:panic("E004", node)
    end

    if op_sym == "@index" then
        --   1-based (Teal) 到 0-based (Nelua/C) 的平移，增加物理隔离防御优先级坍塌
        return self:gen(node.e1) .. "[((" .. self:gen(node.e2) .. ") - 1)]"
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
