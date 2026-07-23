-- @l2c_import: std/multicore.tl
-- @l2c_import: std/ringbuffer.tl
-- @l2c_include: sched.h

local type C_LIBC = record
    sched_yield: function()
end

local type SharedState = record
    sum: integer
    done: integer
    _cast: function(any): SharedState
end

local function Get_SharedState(): SharedState
    return SharedState._cast(L2C_Static("SharedState"))
end

local function Get_SharedQueue(): SPSC_Queue
    return SPSC_Queue._cast(L2C_Static("SPSC_Queue"))
end

local function task_core1()
    local st = Get_SharedState()
    local q = Get_SharedQueue()
    
    --  使用 IntBox 指针作为传出参数，完美匹配 std/ringbuffer.tl 的要求！
    local out = IntBox._new()
    local local_sum = 0
    
    while st.done == 0 do
        if SPSC_Pop(q, out) then
            local_sum = local_sum + out.val
        else
            C_LIBC.sched_yield() -- 队列空了，把 CPU 时间片让给 Core 0
        end
    end
    
    local draining = true
    while draining do
        if SPSC_Pop(q, out) then
            local_sum = local_sum + out.val
        else
            draining = false
        end
    end
    
    st.sum = local_sum
    L2C_Memory_Barrier()
end

print("==== L2C 无锁 SPSC 环形队列极限吞吐测试 ====")

local st = Get_SharedState()
local q = Get_SharedQueue()
st.sum = 0
st.done = 0

local buf_ptr = L2C_Static("[1024]integer")
SPSC_Init(q, 1024, L2C_PtrAsInt(buf_ptr))

Multicore_Launch(L2C_FuncPtr(task_core1))

local push_count = 1000000
for i = 1, push_count do
    while not SPSC_Push(q, 1) do 
        C_LIBC.sched_yield() -- 队列满了，把 CPU 时间片让给 Core 1
    end
end

L2C_Memory_Barrier()
st.done = 1

local wait_done = false
while not wait_done do
    L2C_Memory_Barrier()
    if st.sum > 0 then wait_done = true end
    C_LIBC.sched_yield()
end

print("Core 0 发送总量: ", push_count)
print("Core 1 结算总和: ", st.sum)