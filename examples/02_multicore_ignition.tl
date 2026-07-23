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

local function Get_SharedPayload(): SharedPayload
    return SharedPayload._cast(L2C_Static("SharedPayload"))
end

--  Core 1 物理线程执行
local function task_core1()
    local payload = Get_SharedPayload()
    for i = 1, 1000000 do
        L2C_Spinlock_Lock(0)
        payload.core1_count = payload.core1_count + 1
        payload.total_ops = payload.total_ops + 1
        L2C_Spinlock_Unlock(0)
    end
end

print("==== L2C 双核真实物理交错测试 ====")

local payload = Get_SharedPayload()
payload.core0_count = 0
payload.core1_count = 0
payload.total_ops = 0

--  点火！启动 Core 1
Multicore_Launch(L2C_FuncPtr(task_core1))

-- Core 0 计算：100万次
for i = 1, 1000000 do
    L2C_Spinlock_Lock(0)
    payload.core0_count = payload.core0_count + 1
    payload.total_ops = payload.total_ops + 1
    L2C_Spinlock_Unlock(0)

    --  [关键补丁]：每 100 次循环让出 1 微秒，打破 Core 0 的连续霸锁！
    if i % 100 == 0 then
        C_LIBC.usleep(1)
    end

    --  [半程采样]：Core 0 跑到 50 万次时采样
    if i == 500000 then
        L2C_Spinlock_Lock(0)
        local c1_snapshot = payload.core1_count
        L2C_Spinlock_Unlock(0)
        print("[半程采样] Core 0 进度 50% 时，Core 1 进度为: ", c1_snapshot)
    end
end

print("Core 0 完工，等待 Core 1 汇合...")
local done = false
while not done do
    L2C_Spinlock_Lock(0)
    if payload.core1_count == 1000000 then
        done = true
    end
    L2C_Spinlock_Unlock(0)
    C_LIBC.usleep(100)
end

print("Core 0 贡献: ", payload.core0_count)
print("Core 1 贡献: ", payload.core1_count)
print("总计操作数: ", payload.total_ops)