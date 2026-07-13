-- examples/16_uv_timer.tl
-- @l2c_import: std/uv.tl

-- 申明魔法宏
local function L2C_Buffer(size: integer): any end
local function L2C_Ref(var: any): any end

-- 1. 这是一个极其纯粹的 C 原生回调函数！
-- 在底层，它就是一个地址。当定时器触发，操作系统内核会直接 Call 它。
local function my_timer_cb(handle: any)
    print("⏰ [Libuv 异步事件] C 语言内核回调触发！延迟极低！")
end

-- 2. 启动心脏
print("🚀 初始化 Libuv 事件驱动引擎...")
local loop = C_UV.uv_default_loop()

-- 在栈上强开 256 字节，用来存放 uv_timer_t 结构体实体 (绝对够用，防止溢出)
local my_timer = L2C_Buffer(256)
C_UV.uv_timer_init(loop, L2C_Ref(my_timer))

print("⏳ 挂载 1000 毫秒异步定时器，事件循环启动...")
-- 传入 my_timer 的物理指针，以及我们 Lua 函数的物理地址 (my_timer_cb)
-- 延迟 1000ms，重复间隔 0 (不重复)
-- 🔥 [降维打击]：传入 my_timer 的物理指针，并将 Lua 函数强制降维为 C 回调指针！
C_UV.uv_timer_start(L2C_Ref(my_timer), L2C_FuncPtr(my_timer_cb), 1000, 0)

-- 3. 阻塞执行，将线程控制权交给操作系统的事件轮询 (epoll / kqueue)
C_UV.uv_run(loop, 0)

print("✅ 事件处理完毕，主线程安全退出。")
