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

-- [核心修复]: 返回 any (void*)，彻底杜绝 L2C 生成 C 语言的按值返回！
local function Get_SharedState_Ptr(): any
    return L2C_Static("SharedState")
end

local function task_core1()
    -- 获取物理指针并原地强转，此时 C 语言底层对应的是 `SharedState* st = ...` (绝对操作同一块内存)
    local st_ptr = Get_SharedState_Ptr()
    local st = SharedState._cast(st_ptr)
    
    local local_sum = 0
    
    while st.done == 0 do
        -- 启用终极 0-GC 多返回值宏！斩断一切 Box 对象！
        local ok, val = SPSC_PopDefault()
        if ok then
            local_sum = local_sum + val
        else
            C_LIBC.sched_yield() -- 队列空了，把 CPU 时间片让给 Core 0
        end
    end
    
    local draining = true
    while draining do
        local ok, val = SPSC_PopDefault()
        if ok then
            local_sum = local_sum + val
        else
            draining = false
        end
    end
    
    st.sum = local_sum
    L2C_Memory_Barrier()
end

print("==== L2C 无锁 SPSC 环形队列极限吞吐测试 ====")

-- 同样在主核侧执行指针强转
local st_ptr = Get_SharedState_Ptr()
local st = SharedState._cast(st_ptr)
st.sum = 0
st.done = 0

-- 傻瓜式一键初始化，无需再手动获取队列和缓冲区指针！
SPSC_InitDefault()

Multicore_Launch(task_core1)

local push_count = 1000000
for i = 1, push_count do
    while not SPSC_PushDefault(1) do 
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