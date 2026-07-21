-- @l2c_import: std/multicore.tl
-- @l2c_include: unistd.h

local type C_LIBC = record
    usleep: function(integer)
end

local type SharedPayload = record
    core0_count: integer
    core1_count: integer
    total_ops: integer
    _cast: function(any): SharedPayload
end

-- 🛡️ 包装成单例函数，确保两个核拿到同一个物理地址
local function Get_SharedPayload(): SharedPayload
    return SharedPayload._cast(L2C_Static("SharedPayload"))
end

-- 🚀 Core 1 物理线程执行的黑洞函数
local function task_core1()
    local payload = Get_SharedPayload()
    for i = 1, 100000 do
        L2C_Spinlock_Lock(0)      -- 🔒 抢占物理总线
        payload.core1_count = payload.core1_count + 1
        payload.total_ops = payload.total_ops + 1
        L2C_Spinlock_Unlock(0)    -- 🔓 释放总线
    end
end

print("==== L2C 双核并发点火测试 ====")

local payload = Get_SharedPayload()
payload.core0_count = 0
payload.core1_count = 0
payload.total_ops = 0

-- 🚀 点火！
Multicore_Launch(L2C_FuncPtr(task_core1))

-- Core 0 计算
for i = 1, 100000 do
    L2C_Spinlock_Lock(0)
    payload.core0_count = payload.core0_count + 1
    payload.total_ops = payload.total_ops + 1
    L2C_Spinlock_Unlock(0)
end

-- 物理屏障 (Barrier)
print("Core 0 完工，等待 Core 1 汇合...")
local done = false
while not done do
    L2C_Spinlock_Lock(0)
    if payload.core1_count == 100000 then
        done = true
    end
    L2C_Spinlock_Unlock(0)
    
    -- 🛡️ [防饥饿补丁]：强制让出 OS 调度权，给 Core 1 抢锁的机会
    C_LIBC.usleep(100)
end

print("Core 0 贡献: ", payload.core0_count)
print("Core 1 贡献: ", payload.core1_count)
print("总计操作数: ", payload.total_ops)

-- EXPECT: ====L2C双核并发点火测试====Core0完工，等待Core1汇合...Core0贡献:100000Core1贡献:100000总计操作数:200000