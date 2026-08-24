-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C 极客环境声明库 (L2C Hacker Encyclopedia & Language Server Definitions)
-- 警告：此文件仅作为 IDE 视觉欺骗与智能提示使用，在 L2C 物理域编译时将被瞬间抹除。
-- ==============================================================================

-- ==========================================
-- 1. L2C 核心魔法宏 (Core Intrinsics)
-- ==========================================

--- **【0-GC 栈内存】** 申请一段定长的连续 C 语言栈内存 (底层映射为 `char buf[size]`)。离开作用域瞬间销毁，绝对零开销。
--- @param size 字节大小。
--- @return 返回该物理内存的无类型指针 `(void*)`。
global L2C_Buffer: function(size: integer): any

--- **【0-GC 栈数组】** 申请一段连续的 `double` 物理数组内存。
--- @param size 数组长度。
global L2C_NumberArray: function(size: integer): {number}

--- **【0-GC 栈数组】** 申请一段连续的 `int64_t/int32_t` 物理数组内存。
--- @param size 数组长度。
global L2C_IntegerArray: function(size: integer): {integer}

--- **【物理引用】** 获取变量的 C 语言取地址指针，等同于 `&var`。必须配合指针函数使用。
--- @param var 目标栈变量或静态变量。
global L2C_Ref: function(var: any): any

--- **【零拷贝强转】** L2C 的核心 OOP 魔法！直接将裸指针映射为指定类型结构体，0 纳秒解析延迟。
--- @param ptr 物理内存指针 `(void*)`。
--- @param tname 目标结构体类型名称。
global L2C_Cast: function(ptr: any, tname: string): any

--- **【函数降维】** 剥离 Teal 运行期闭包，强制降维为 C 语言可执行的纯物理函数指针 `(void (*)(void))`。
--- @param func 目标静态局部函数。
global L2C_FuncPtr: function(func: any): any

--- **【空指针】** 分配一个未初始化的裸 C 指针 (`NULL`)。
global L2C_NewPointer: function(): any

--- **【内存重置】** 瞬间清空当前物理核心独占的 Arena 内存池。`O(1)` 极速重置，防 OOM 必备，通常置于 Tick 末尾。
global L2C_Tick_Reset: function()

--- **【静态共享内存】** 从当前核心的 Arena 或 BSS 段分配一块绝对物理安全的静态内存，适合跨核/跨 Tick 共享。
--- @param type_name 结构体或数组标识符 (如 "SharedPayload" 或 "[1024]integer")。
global L2C_Static: function(type_name: any): any

--- **【防踩踏锁】** 全平台一致的硬件级自旋锁 (Spinlock)。抢占物理总线，防死锁。
--- @param lock_id 锁通道 ID (0 ~ 7)。
global L2C_Spinlock_Lock: function(lock_id: integer)

--- **【解锁】** 释放指定通道的硬件自旋锁。必须与 Lock 绝对配对！
--- @param lock_id 锁通道 ID (0 ~ 7)。
global L2C_Spinlock_Unlock: function(lock_id: integer)

--- **【物理屏障】** 纯汇编级全内存屏障 (`__sync_synchronize`)，强制阻断 CPU 的流水线乱序执行。
global L2C_Memory_Barrier: function()

--- **【极客降维】** 突破类型系统，将物理指针双重强转为等宽的 CPU 整数 (`ptrdiff_t`)，碾压 32/64 位警告。
--- @param ptr 物理内存指针。
global L2C_PtrAsInt: function(ptr: any): integer

--- **【数据降维】** 突破强类型限制，将浮点数 (number) 强转为等宽整数 (integer)，直接截断小数部分。
--- @param n 浮点数。
global L2C_NumberToInt: function(n: number): integer

-- ==========================================
-- 2. SPSC 无锁环形队列 (std/spsc.tl)
-- ==========================================

global type SPSC_Queue = record
    head: integer
    tail: integer
    mask: integer
    data_ptr: integer
    _cast: function(any): SPSC_Queue
end

--- **【装箱指针】** 强类型的物理整数盒子，用于替代数组进行 C 语言 Out-Parameter 指针传出。
global type IntBox = record
    val: integer
    _new: function(): IntBox
    _cast: function(any): IntBox
end

--- **【无锁队列初始化】** 原地强转指针初始化 0-GC 无锁环形队列。
--- @param q_ptr 队列物理指针 (`void*`)
--- @param power_of_2_size 容量（极其严格：必须为 2 的幂次方）
--- @param ptr_as_int 数据缓冲区物理地址整数 (`L2C_PtrAsInt`)
global SPSC_Init: function(q_ptr: any, power_of_2_size: integer, ptr_as_int: integer)

--- **【无锁流水线: 生产】** 生产者非阻塞极速压入数据。
--- @param q_ptr 队列物理指针
--- @param val 压入的 64位/32位 整数
--- @return 是否成功 (队列满则触发 false，需业务层自旋或让出 CPU)
global SPSC_Push: function(q_ptr: any, val: integer): boolean

--- **【无锁流水线: 消费】** 消费者非阻塞极速弹出数据。
--- @param q_ptr 队列物理指针
--- @param out_box_ptr 接收数据的 `IntBox` 物理指针
--- @return 是否成功 (队列空返回 false)
global SPSC_Pop: function(q_ptr: any, out_box_ptr: any): boolean


-- ==========================================
-- 3. 树莓派 Pico 硬件接口 (std/pico.tl)
-- ==========================================

--- **【Pico 硬件】** GPIO 输出模式 (1)
global PICO_GPIO_OUT: integer
--- **【Pico 硬件】** GPIO 输入模式 (0)
global PICO_GPIO_IN: integer

global type C_PICO_TYPE = record
    --- 初始化单片机所有的标准输入输出 (UART/USB)。
    stdio_init_all: function()
    --- 初始化指定 GPIO 引脚。
    gpio_init: function(pin: integer)
    --- 设置 GPIO 引脚方向 (使用 PICO_GPIO_OUT / PICO_GPIO_IN)。
    gpio_set_dir: function(pin: integer, dir: integer)
    --- 设置 GPIO 电平 (1 为高，0 为低)。
    gpio_put: function(pin: integer, val: integer)
    --- 唤醒 ADC 硬件模块。
    adc_init: function()
    --- 初始化指定的 ADC 物理引脚 (通常为 26, 27, 28)。
    adc_gpio_init: function(pin: integer)
    --- 选择 ADC 采集通道 (0, 1, 2)。
    adc_select_input: function(channel: integer)
    --- 阻塞式读取当前 ADC 通道电压值 (12-bit, 0~4095)。
    adc_read: function(): integer
    --- 纳秒级硬实时休眠。精准挂起当前物理核心，绝不触发任务切换。
    sleep_us: function(us: integer)
    --- 将纯 C 闭包发射至 Core 1 物理核心执行。
    multicore_launch_core1: function(func_ptr: any)
    --- 利用 RP2040 SIO 硬件 FIFO 向副核压入数据。
    multicore_fifo_push_blocking: function(data: integer)
    --- 从 SIO 硬件 FIFO 阻塞读取副核发来的数据。
    multicore_fifo_pop_blocking: function(): integer
    --- 获取当前物理核心的 ID (0 或 1)。
    get_core_num: function(): integer
end

--- **【RP2040】** 树莓派 Pico 底层硬件映射命名空间。
global C_PICO: C_PICO_TYPE


-- ==========================================
-- 4. DSP 数字信号处理 (std/dsp.tl)
-- ==========================================

--- **【0-GC DSP】** 浮点 Goertzel 算法：以极低 CPU 消耗侦测指定频点的绝对能量（不含开方开销）。
--- @param samples 采样点内存指针 (必须预先去除直流偏置)
--- @param coeff 预先算好的目标频率系数
--- @param n 采样点数
global dsp_goertzel_mag: function(samples: {number}, coeff: number, n: integer): number

--- **【0-GC DSP】** Q15 定点数 Goertzel：纯整数极限单周期运算！完美防溢出，无 FPU 单片机的终极杀器。
--- @param samples 整数型采样点指针
--- @param coeff_q15 Q15 定点数系数 = round(2 * cos(2*pi*f/fs) * 32768)
--- @param n 采样点数
global dsp_goertzel_mag_q15: function(samples: {integer}, coeff_q15: integer, n: integer): integer


-- ==========================================
-- 5. ESP32 & FreeRTOS 实时系统
-- ==========================================

--- **【ESP32 硬件】** GPIO 输出模式
global ESP_GPIO_MODE_OUTPUT: integer

--- **【FreeRTOS】** 毫秒级延时 (自动向下取整分配 Tick)
global esp32_delay_ms: function(ms: integer)

--- **【FreeRTOS】** 利用 L2C_FuncPtr 强转任务指针，创建独立的 RTOS Task。
global freertos_create_task: function(name: string, func_ptr: any)
global freertos_delay_ms: function(ms: integer)
global freertos_start: function()

--- **【SMP 点火】** 全平台一致 API：发射业务函数到物理 Core 1 (PC 映射为 Pthread，MCU 映射为物理核)。
global Multicore_Launch: function(task_func: any)


-- ==========================================
-- 6. HFT 高频网络与消息队列 (ZMQ, Nanomsg)
-- ==========================================

global type zmq_context_t = record end
global type zmq_socket_t = record end

global type C_ZMQ_TYPE = record
    --- **【ZMQ】** 初始化并获取 0-MQ 极速上下文。
    zmq_ctx_new: function(): zmq_context_t
    --- **【ZMQ】** 创建指定模式的 Socket (如 PUB/SUB, REQ/REP)。
    zmq_socket: function(ctx: zmq_context_t, type: integer): zmq_socket_t
    --- **【ZMQ】** 建立底层的 TCP/IPC 连接。
    zmq_connect: function(sk: zmq_socket_t, endpoint: string): integer
    zmq_setsockopt: function(sk: zmq_socket_t, option: integer, optval: any, optvallen: integer): integer
    --- **【ZMQ 零拷贝】** 直接将网络字节流覆盖到 L2C 物理 Buffer 中！
    zmq_recv: function(sk: zmq_socket_t, buf: any, len: integer, flags: integer): integer
end

--- **【ZMQ】** 高频交易最爱的 ZeroMQ 底层 C 绑定库。
global C_ZMQ: C_ZMQ_TYPE

global type C_NN_TYPE = record
    nn_socket: function(domain: integer, protocol: integer): integer
    nn_bind: function(sk: integer, endpoint: string): integer
    nn_connect: function(sk: integer, endpoint: string): integer
    nn_setsockopt: function(sk: integer, level: integer, option: integer, optval: any, optvallen: integer): integer
    nn_send: function(sk: integer, buf: any, len: integer, flags: integer): integer
    nn_recv: function(sk: integer, buf: any, len: integer, flags: integer): integer
    nn_close: function(sk: integer): integer
end

--- **【Nanomsg】** 极致轻量的 C 语言微型消息队列。
global C_NN: C_NN_TYPE

global NN_AF_SP: integer
global NN_PUB: integer
global NN_SUB: integer
global NN_SUB_SUBSCRIBE: integer
global NN_DONTWAIT: integer

global type C_XDP_TYPE = record
    --- **【内核旁路】** Linux XDP eBPF 极速收包网关，直接接管网卡环形缓冲区！
    xdp_start_poll: function(if_name: string, callback: any)
    ntohs: function(netshort: integer): integer
    ntohl: function(netlong: integer): integer
end
global C_XDP: C_XDP_TYPE


-- ==========================================
-- 7. 极速 JSON 解析 (std/simdjson & cjson)
-- ==========================================

global type simd_ptr = record end
global type C_SIMD_TYPE = record
    simdjson_c_parse: function(string, integer): simd_ptr
    simdjson_c_get_number: function(simd_ptr, string): number
    simdjson_c_free: function(simd_ptr)
end

global C_SIMD: C_SIMD_TYPE

--- **【simdjson】** 利用 AVX/NEON 向量指令集进行千兆字节每秒的零拷贝 JSON 解析！
global SIMDJSON_Parse: function(json_str: string): simd_ptr
--- **【simdjson】** 0-GC 提取数值字段，绝不产生临时字符串。
global SIMDJSON_GetNumber: function(obj: simd_ptr, key: string): number
global SIMDJSON_Free: function(obj: simd_ptr)

global type cJSON_ptr = record end
global type C_CJSON_TYPE = record
    cJSON_Parse: function(any): cJSON_ptr
    cJSON_GetObjectItemCaseSensitive: function(cJSON_ptr, string): cJSON_ptr
    cJSON_IsNumber: function(cJSON_ptr): integer
    cJSON_IsString: function(cJSON_ptr): integer
    cJSON_GetNumberValue: function(cJSON_ptr): number
    cJSON_GetStringValue: function(cJSON_ptr): string
    cJSON_Delete: function(cJSON_ptr)
end

global C_CJSON: C_CJSON_TYPE

global CJSON_ParseString: function(json_str: string): cJSON_ptr
global CJSON_GetNumber: function(obj: cJSON_ptr, key: string): number
global CJSON_Free: function(obj: cJSON_ptr)


-- ==========================================
-- 8. 系统时间与持久化 (Time, SQLite, UV)
-- ==========================================

global TIME_CLOCK_REALTIME: integer
global TIME_CLOCK_MONOTONIC: integer

--- **【硬实时时钟】** 获取纳秒 (Nanosecond) 级高精度系统绝对时间。
global time_now_ns: function(): integer

global type sqlite3_t = record
    _ptr: function(): sqlite3_t
end

global SQLITE_OK: integer

global type uv_loop_t = record end
global type C_UV_TYPE = record
    uv_default_loop: function(): uv_loop_t
    uv_timer_init: function(loop: uv_loop_t, timer_req: any): integer
    uv_timer_start: function(timer_req: any, callback: any, timeout: integer, repeat_ms: integer): integer
    uv_run: function(loop: uv_loop_t, mode: integer): integer
end
--- **【libuv】** Node.js 底层的 C 语言全异步事件驱动引擎！
global C_UV: C_UV_TYPE

global type C_SQLITE_TYPE = record
    --- 打开 SQLite 本地持久化数据库。
    sqlite3_open: function(filename: string, db_ptr: any): integer
    --- 直接以纯 C 字符串执行 SQL 语句，回调函数需通过 L2C_FuncPtr 强转。
    sqlite3_exec: function(db: any, sql: string, callback: any, arg: any, errmsg: any): integer
    --- 关闭释放数据库连接。
    sqlite3_close: function(db: any): integer
end
--- **【SQLite FFI】** 世界最强微型数据库的 C 底层映射。
global C_SQLITE: C_SQLITE_TYPE