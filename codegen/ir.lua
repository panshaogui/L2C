-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- codegen/ir.lua
-- L2C-LIR: 零开销 (0-GC) 的底层硬件与内存布局抽象描述

local IR = {}
IR.Type = {}

-- 1. 基础标量 (如 integer, boolean, cstring, Record 名称)
function IR.Type.Primitive(name)
    return {
        kind = "Primitive",
        name = name,
        -- 降维触手：提供向 Nelua/C 物理层的映射
        to_nelua = function(self) return self.name end
    }
end

-- 2. 0-GC 裸指针 (void* 泛型指针 或 Type* 强类型指针)
function IR.Type.Pointer(inner_type)
    return {
        kind = "Pointer",
        inner = inner_type,
        to_nelua = function(self) 
            if self.inner then 
                return "pointer(" .. self.inner:to_nelua() .. ")" 
            end
            return "pointer" 
        end
    }
end

-- 3. 物理连续内存切片 (Span)
function IR.Type.Span(element_type)
    return {
        kind = "Span",
        element_type = element_type,
        to_nelua = function(self) 
            return "span(" .. self.element_type:to_nelua() .. ")" 
        end
    }
end

-- 4. 函数指针类型 (用于 FFI 回调或闭包降维)
function IR.Type.Function()
    return {
        kind = "Function",
        to_nelua = function(self) return "function()" end
    }
end

return IR