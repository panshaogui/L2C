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

local function Get_SharedQueue(): SPSC_Queue
    return SPSC_Queue._cast(L2C_Static("SPSC_Queue"))
end

-- ==============================================================================
-- 封装扩展：默认跨核通道分配器 (0-GC 多返回值终极版)
-- ==============================================================================

-- 1. 获取全局唯一的默认队列指针
-- 核心旧伤修复：去掉 SPSC_Queue._cast，直接返回 L2C_Static，避免底层的按值拷贝！
global function SPSC_GetDefaultQueue(): any
    return L2C_Static("SPSC_Queue")
end

-- 2. 获取默认的物理内存数组 (1024 长度)
global function SPSC_GetDefaultBuffer(): integer
    return L2C_PtrAsInt(L2C_Static("[1024]integer"))
end

-- 3. 傻瓜式一键初始化
global function SPSC_InitDefault()
    SPSC_Init(SPSC_GetDefaultQueue(), 1024, SPSC_GetDefaultBuffer())
end

-- 4. 傻瓜式极速推送
global function SPSC_PushDefault(val: integer): boolean
    return SPSC_Push(SPSC_GetDefaultQueue(), val)
end

-- 5. 斩龙魔法：多返回值弹出！(彻底遵循 C 语言内存法则)
global function SPSC_PopDefault(): boolean, integer
    -- 在栈上开辟纯净的 8 字节物理缓冲 (绝对 0-GC)
    local buf = L2C_Buffer(8)
    
    -- 将缓冲指针透传给底层，由底层填入数据
    local ok = SPSC_Pop(SPSC_GetDefaultQueue(), L2C_Ref(buf))
    
    local val = 0
    if ok then
        -- 核心修复：将栈缓冲原地强转为 IntBox 结构体，合法读取内存！免疫优化器抹杀！
        local box = IntBox._cast(L2C_Ref(buf))
        val = box.val
    end
    
    return ok, val
end