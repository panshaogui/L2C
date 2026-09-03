-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- std/cmd_queue.tl
-- L2C 0-GC 跨核无锁命令队列 (SPSC RingBuffer)

local type C_SPSC = record
    l2c_spsc_read_arr: function(integer, integer): integer
    l2c_spsc_write_arr: function(integer, integer, integer)
    l2c_memory_barrier: function()
end

-- 强制封装为 Getter 函数，确保 Core 0 和 Core 1 拿到的是全宇宙同一块物理静态内存！
local function Get_CmdQueue(): any return L2C_Static("[256]integer") end
local function Get_CmdHead(): any return L2C_Static("integer") end
local function Get_CmdTail(): any return L2C_Static("integer") end

local function CMD_Push(val: integer)
    local q = L2C_PtrAsInt(Get_CmdQueue())
    local head_ptr = L2C_PtrAsInt(Get_CmdHead())
    local head = C_SPSC.l2c_spsc_read_arr(head_ptr, 0)
    
    local next_head = (head + 1) & 255 
    
    C_SPSC.l2c_spsc_write_arr(q, head, val)
    C_SPSC.l2c_memory_barrier()  -- 物理内存屏障，防编译器指令重排！
    C_SPSC.l2c_spsc_write_arr(head_ptr, 0, next_head)
end

local function CMD_Pop(): boolean, integer
    local q = L2C_PtrAsInt(Get_CmdQueue())
    local head_ptr = L2C_PtrAsInt(Get_CmdHead())
    local tail_ptr = L2C_PtrAsInt(Get_CmdTail())
    
    local head = C_SPSC.l2c_spsc_read_arr(head_ptr, 0)
    local tail = C_SPSC.l2c_spsc_read_arr(tail_ptr, 0)
    
    if head == tail then return false, 0 end
    
    local val = C_SPSC.l2c_spsc_read_arr(q, tail)
    local next_tail = (tail + 1) & 255
    C_SPSC.l2c_spsc_write_arr(tail_ptr, 0, next_tail)
    
    return true, val
end