-- examples/16_uv_timer.tl
-- @l2c_import: std/uv.tl

-- Libuv 的回调签名必须接收一个 handle 参数！
local function my_timer_cb(handle: any)
    print(" [Libuv 异步事件] C 语言内核回调触发！延迟极低！")
end

print(" 初始化 Libuv 事件驱动引擎...")
local loop = UV_DefaultLoop()

-- 在主函数的栈上申请 256 字节
local my_timer = L2C_Buffer(256)

-- 使用 L2C_Ref 显式获取这块栈内存的绝对物理地址！
UV_TimerInit(loop, L2C_Ref(my_timer))
print(" 挂载 1000 毫秒异步定时器，事件循环启动...")

-- 同时传入内存地址和回调函数的指针
UV_TimerStart(L2C_Ref(my_timer), L2C_FuncPtr(my_timer_cb), 1000, 0)
UV_Run(loop)
print(" 事件处理完毕，主线程安全退出。")