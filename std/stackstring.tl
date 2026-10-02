-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- std/stackstring.tl
-- L2C 0-GC 栈内存定长字符串库 (StackString)

-- @l2c_include: clib/stackstring.h
-- @l2c_source: clib/stackstring.c

-- L2C FFI 探针 (类型绝对安全降维)
global type C_STACKSTR = record
    l2c_str_init: function(any)
    l2c_str_clear: function(any)
    l2c_str_append_char: function(any, integer, integer)
    l2c_str_append_cstr: function(any, integer, string)
    l2c_str_get: function(any): string
    l2c_str_len: function(any): integer
    l2c_str_eq: function(any, string): integer
    l2c_str_to_int: function(any): integer
    l2c_str_append_int: function(any, integer, integer)

    l2c_str_startswith: function(any, string): integer
    l2c_str_parse_int: function(any, integer): integer
    l2c_str_parse_hex: function(any, integer): integer
    l2c_str_copy: function(any, any, integer)
end

global function StackStr_init(ptr: any)
    C_STACKSTR.l2c_str_init(ptr)
end

global function StackStr_clear(ptr: any)
    C_STACKSTR.l2c_str_clear(ptr)
end

global function StackStr_append_char(ptr: any, max_len: integer, c: integer)
    C_STACKSTR.l2c_str_append_char(ptr, max_len, c)
end

global function StackStr_append_str(ptr: any, max_len: integer, str: string)
    C_STACKSTR.l2c_str_append_cstr(ptr, max_len, str)
end

global function StackStr_append_int(ptr: any, max_len: integer, val: integer)
    C_STACKSTR.l2c_str_append_int(ptr, max_len, val)
end

global function StackStr_get(ptr: any): string
    return C_STACKSTR.l2c_str_get(ptr)
end

global function StackStr_len(ptr: any): integer
    return C_STACKSTR.l2c_str_len(ptr)
end

global function StackStr_eq(ptr: any, cmp: string): boolean
    return C_STACKSTR.l2c_str_eq(ptr, cmp) == 1
end

global function StackStr_to_int(ptr: any): integer
    return C_STACKSTR.l2c_str_to_int(ptr)
end

global function StackStr_startswith(ptr: any, prefix: string): boolean
    return C_STACKSTR.l2c_str_startswith(ptr, prefix) == 1
end

global function StackStr_parse_int(ptr: any, offset: integer): integer
    return C_STACKSTR.l2c_str_parse_int(ptr, offset)
end

global function StackStr_parse_hex(ptr: any, offset: integer): integer
    return C_STACKSTR.l2c_str_parse_hex(ptr, offset)
end

global function StackStr_copy(dest: any, src: any, max_len: integer)
    C_STACKSTR.l2c_str_copy(dest, src, max_len)
end