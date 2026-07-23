-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- ==============================================================================
-- L2C 极简标准库：SPSC 无锁环形队列 (强制指针引用版)
-- ==============================================================================

local type C_SPSC = record
    l2c_spsc_read_arr: function(integer, integer): integer
    l2c_spsc_write_arr: function(integer, integer, integer)
end

local type SPSC_Queue = record
    head: integer
    tail: integer
    mask: integer
    data_ptr: integer  
    _cast: function(any): SPSC_Queue
end

local type IntBox = record
    val: integer
    _new: function(): IntBox
    _cast: function(any): IntBox
end

--  参数强制改为 any (void*)，彻底杜绝 C 语言的按值拷贝！
local function SPSC_Init(q_ptr: any, power_of_2_size: integer, ptr_as_int: integer)
    -- 原地强转为物理指针进行写入
    local q = SPSC_Queue._cast(q_ptr)
    q.head = 0
    q.tail = 0
    q.mask = power_of_2_size - 1
    q.data_ptr = ptr_as_int
    L2C_Memory_Barrier()
end

local function SPSC_Push(q_ptr: any, val: integer): boolean
    local q = SPSC_Queue._cast(q_ptr)
    L2C_Memory_Barrier() 
    local next_head = (q.head + 1) & q.mask
    if next_head == q.tail then return false end
    
    C_SPSC.l2c_spsc_write_arr(q.data_ptr, q.head, val)
    L2C_Memory_Barrier() 
    q.head = next_head
    return true
end

local function SPSC_Pop(q_ptr: any, out_box_ptr: any): boolean
    local q = SPSC_Queue._cast(q_ptr)
    local out_box = IntBox._cast(out_box_ptr)
    L2C_Memory_Barrier() 
    if q.head == q.tail then return false end
    
    out_box.val = C_SPSC.l2c_spsc_read_arr(q.data_ptr, q.tail)
    L2C_Memory_Barrier() 
    q.tail = (q.tail + 1) & q.mask
    return true
end