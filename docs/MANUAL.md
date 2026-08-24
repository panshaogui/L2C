# L2C (Lua-to-C) 终极极客使用手册

**Transpile Typed Lua directly into 0-GC Native C.**

L2C 并不是一个通用的 Lua 编译器，而是一个专为 **高频交易 (HFT)**、低延迟网关和内核级信号处理打造的 **物理级安全子集**。它将高级脚本语言（Teal）的优雅，以“零开销抽象”的方式，降维编译成压榨硬件极限的纯 C 二进制代码。

⚠️ **警告：阅读使用前必须了解的铁律**
L2C **物理阉割了垃圾回收（GC）**。在这里，没有闭包，没有动态表，没有运行期 `Any`，没有字符串拼接。如果你需要这些，请退回 LuaJIT；如果你渴望获得 **30KB 体积、50万+ msg/s 吞吐量、纳秒级无抖动** 的绝对力量，请继续阅读。

---

## 一、 环境部署与编译构建

L2C 编译器本身已被打包为单文件二进制可执行程序 `l2c_bin`。

### 1. 编译命令
```bash
./l2c_bin <入口文件.tl> [-o <输出二进制名>]
```
执行后，L2C 会自动完成 AST 解析、物理拼接、C 语言转换，并唤醒操作系统的 `Clang` 编译器开启 `-O3 -march=native -flto` 硬件级极限优化。

### 2. Apple Silicon (M系芯片) 自动适配
L2C 编译器内置了针对 Mac M系列芯片的物理寻址雷达。当检测到需要链接 C 库时，会自动挂载 `/opt/homebrew/include` 和 `/opt/homebrew/lib`。

---

## 二、 Unity Build：跨模块工程组织

在 0-GC 的世界里，传统的 `require` 模块会导致不可控的内存分配。L2C 采用 **Unity Build (物理拼接)** 的方式组织大型工程。

**绝对禁令**：禁止使用 `require` 导入本地模块！
**正确姿势**：在文件顶部使用元注释进行源码级拼接：

```lua
-- @l2c_import: std/zmq.tl
-- @l2c_import: utils/math_ext.tl
```
L2C 在编译期会将依赖文件如 C 语言的 `#include` 一样，在词法作用域内原地平铺展开，彻底消灭模块调用的性能损耗。

---

## 三、 极速内存管理 (核心语法)

在 L2C 中，内存只有两种合法归宿：**物理栈 (Stack)** 与 **Tick 级竞技场 (Arena)**。所有的内存分配都在编译期被强制内联，无任何函数调用开销。

### 1. 栈内存 (极速、用完即毁)
利用全局魔法宏，在 C 函数栈上强开连续内存：
```lua
-- 1. 开辟 1024 字节的纯 C 空白缓冲 (等价于 char buf[1024])
local buf = L2C_Buffer(1024)

-- 2. 开辟强类型定长数组 (高层返回 {number}，底层映射 [256]number)
local fft_data = L2C_NumberArray(256)
local ids = L2C_IntegerArray(10)
```

### 2. 竞技场内存 (Tick级生命周期)
L2C 引擎自带一个 10MB 的 Arena 内存池。用于存放跨函数传递的业务对象（如 `Order`）。
```lua
local type Order = record
    price: integer
    qty: integer
    _new: function(integer): Order -- 声明构造函数
end

-- 1. 自动兜底实例化：底层将在 Arena 极速分配内存。
-- 缺失的 qty 参数会被编译器自动安全兜底为 0，防止 C 语言脏内存！
local o = Order._new(45000)

-- 2. O(1) 瞬时重置：在策略主循环 (While) 的末尾调用，瞬间清空 10MB 内存，拒绝 OOM！
L2C_Tick_Reset()
```

### 3. 零拷贝强转 (Zero-Copy Cast)
针对网卡接收到的纯字节流，不进行任何反序列化，直接原地映射为结构体指针。
```lua
-- L2C_Ref() 用于向底层传递 C 指针 (&buf)
local bytes = C_ZMQ.zmq_recv(sk, L2C_Ref(buf), 1024, 0)

-- L2C_Cast() 直接将栈内存强转为结构体！0 纳秒延迟解析！
local pkt: Order = Order._cast(L2C_Ref(buf))
print(pkt.price)
```

---

## 四、 C FFI：对话物理世界

L2C 允许你直接在脚本中无缝调用操作系统的底层 C 动态/静态库。

### 1. 声明外部库与头文件
在 `.tl` 文件头部使用元注释：
```lua
-- @l2c_link: zmq        (告诉 Clang 链接 libzmq.a / -lzmq)
-- @l2c_include: math.h  (告诉 Clang 引入头文件)
```

### 2. 隔离命名空间与类型降维
使用 `C_` 开头的 Record 声明外部函数。L2C 会在底层将所有 `C_XXX` 合并入唯一的 `c` 命名空间，并自动生成 `<cimport>` 绑定。

```lua
local type C_LIBC = record
    puts: function(string): integer
    -- 注意降维打击：C 语言的 void* 指针，在高层用 any 声明
    memcpy: function(any, any, integer) 
end

-- 调用时，L2C 会自动把 string 转为 cstring，any 转为 void*
C_LIBC.puts("Hello Bare-Metal!")
```

---

## 五、 L2C 标准库 (L2C-STD)

为了避免每次都在业务代码里手写 C 函数签名，我们将顶级 C 库封装在 `std/` 目录下。

### 1. 隐形债清偿机制 (The Debt Registry)
当你引入 `std/zmq.tl` 时，ZMQ 底层实际上依赖了 `libc++` 和 `libsodium`。
L2C 编译器内置了 `STD_DEBT_REGISTRY`（位于 `l2c.lua`）。当你试图静态链接时，L2C 会像雷达一样自动查表，并将底层隐形依赖的链接参数补齐，确保你的策略代码永远只需关注顶层逻辑。

### 2. 如何编写标准库模块
标准库应该保持极度扁平（Flat），不要使用面向对象的 VTable 导出。
```lua
-- std/time.tl 范例
local type C_TIME = record
    clock_gettime: function(integer, any): integer
end

-- 常量和函数加上模块前缀，防止 Unity Build 拼接冲突
local TIME_CLOCK_REALTIME: integer = 0

local function time_now_ns(): integer
    -- 实现逻辑...
end
```
业务层只需 `-- @l2c_import: std/time.tl`，即可直接调用 `time_now_ns()`。

---

## 六、 杂项与语法禁令

*   **字符串拼接禁令**：禁止使用 `a .. b` 进行字符串组合赋值。如果仅仅是为了打印，L2C 编译器提供特权：`print("Price: " .. p)` 会在底层被物理打平为多参数逗号输出 `print("Price: ", p)`，实现 0-GC 打印。
*   **不等于符号**：底层引擎已将 Teal 的 `~=` 与 C 的 `!=` 物理抹平，你在高层写 `~=` 即可。
*   **向下取整除法**：使用 `a // b` 代替 `a / b`，底层将编译为极速的整型汇编指令。

---

# 附录：L2C 新添特性

## 一、 多核并发与硬件锁 (Multicore & Spinlock)

L2C 提供了极其轻量、跨平台（Pico / ESP32 / PC Pthread）的多核并发原语。严禁使用系统级 Mutex，一切以压榨总线性能为核心。

### 多核物理点火器 (`Multicore_Launch`)

将纯逻辑函数一键发射到副核。

> ⚠️ **强制纪律**
> 
> 发射的函数必须使用 `L2C_FuncPtr()` 强转，且**绝对禁止闭包捕获（Closure）**！跨核通信只能通过 `L2C_Static` 共享物理内存。

> ⚠️ **跨核物理通信的“单例铁律”**
>
> `L2C_Static("TypeName")` 的底层本质是 C 语言的局部静态变量宏（`static TypeName o_static;`）。
>
> * **❌ 错误姿势（内存隔离陷阱）**：
>   禁止在 `Core 0` 和 `Core 1` 的执行函数中分别调用 `L2C_Static` 获取同一个对象！这会导致 C 编译器在两个函数作用域里分配出**两块完全不同的物理内存**，引发灾难性的幽灵读写与死锁。
>
> * **✅ 正确姿势（强制单例模式）**：
>   必须将 `L2C_Static` 包装进一个全局的 Getter 函数中（例如 `Get_SharedQueue()`）。确保所有核心调用时进入的是同一个函数作用域，从而拿到全宇宙唯一绝对的物理内存地址！

### **全平台硬件自旋锁 (`L2C_Spinlock_Lock/Unlock`)**：
   在 Pico 上映射为 `hardware_sync` 寄存器，在 ESP32 / PC 上映射为 C11 `stdatomic` 配合汇编级 `yield/pause`。保护共享状态修改，绝不触发 RTOS 任务切换阻塞。

---

## 二、 SPSC 无锁环形流水线 (Zero-Copy IPC)

专为 ADC 采样和 LOB（限价订单簿）撮合设计的跨核通道 `std/ringbuffer.tl`，实现 1,000,000 ops/ms 级极限吞吐。

*   **强制位运算与 2 的幂次方**：
    队列长度必须为 1024, 2048 等 2 的幂次方，利用 `& mask` 完美替代取模运算 `%`。
*   **硬件内存屏障 (`L2C_Memory_Barrier`)**：
    在写数据与改指针之间，强制注入 `__sync_synchronize()` 汇编指令，彻底粉碎 ARM/X86 的流水线乱序执行。
*   **指针降维传递 (`L2C_PtrAsInt`)**：
    为了突破 Teal 前端的强类型限制并规避 C 语言的按值拷贝，使用 `L2C_PtrAsInt(ptr)` 将任意物理内存强转为系统等宽整数 (`ptrdiff_t`)，然后在另一侧用 `_cast` 完美还原。
---

## 三、 IDE 极客体验 (L2C Language Server)

您不需要安装任何笨重的第三方 LSP 插件。
*   只要在根目录保留 `l2c.d.tl` 百科全书文件，L2C 编译器在运行时会自动为您生成 `.vscode/l2c.code-snippets` 和专属的 Hover 插件。
*   在 VSCode 中敲击 `L2C_`，瞬间获得带有赛博荧光青色的高亮、Tab 键参数自动跳转、以及极致详尽的中文 0-GC 物理避坑指南。

---

## 四、 跨维硬件综合 (HLS: Hardware Logic Synthesis)

L2C 的最强杀手锏，在于打破了软件与数字电路的物理壁垒。您可以使用优雅的 Teal/Lua 语法，直接指挥硅片底层的时序状态机与门电路！

### 1. PIO 状态机综合 (针对 RP2040)
只要您的函数名以 `L2C_PIO_` 开头，L2C 编译器将**剥夺其软件执行权**，并自动切断 C 语言的发射。
编译器会对其 AST 进行极度严密的降维打击，直接将内部的 `set`, `jmp`, `out` 函数翻译为 `.pio` 汇编时序逻辑。
*   **特性**：自动剥离字符串双引号（例如 `jmp("!x", "loop")` -> `jmp !x, loop`）。
*   **用途**：实现 0% CPU 占用的 WS2812、I2C、高速 ADC 采样数据泵。

### 2. Verilog RTL 纯硬连线综合 (FPGA/ASIC)
以 `L2C_HDL_` 开头的函数，将被综合为纯正的 Verilog 数字门电路网表！
*   **组合逻辑**：`local x = a ~ b` 将被瞬间综合为绝对零延迟的 `wire x = a ^ b;`。
*   **时序逻辑**：如果函数以 `L2C_HDL_SEQ_` 开头，L2C 会自动注入 `clk` (时钟) 和 `rst_n` (复位) 引脚。遇到 `HDL_Reg(0)` 时，自动生成 D触发器寄存器，并以绝对安全的非阻塞赋值 (`<=`) 放入 `always @(posedge clk)` 时钟块中！

---

## 五、 绝对物理内存掌控 (HFT 级降维)

在金融高频交易与嵌入式底层，内存布局的错位意味着毁灭。L2C 提供了超越 C 语言的强制物理约束。

### 1. 结构体连续阵列 (`L2C_RecordArray`)
禁止使用面向对象的逐个实例化（会导致缓存未命中 Cache Miss）。
```teal
-- 瞬间在底层 Tick 竞技场开辟一块 16KB 的绝对连续物理内存
local ob_ptr = L2C_RecordArray("Order", 1000)
-- 使用魔法签证强转为 Lua 数组，底层自动降维为 C 语言的 (@*[0]Order) 长度为 0 的数组指针！
local ob = Order._cast_arr(ob_ptr)
-- O(1) 物理偏移寻址，L1 Cache 命中率 100%
ob[1].price = 64500
```

### 2. 内存绝对紧凑对齐 (Packed_ 前缀)
为了对接交易所的二进制网卡报文，只要您的 record 命名以 Packed_ 开头：
L2C 将在生成的 C 结构体上强制打上 __attribute__((packed)) 物理烙印，彻底消除编译器的内存间隙 (Padding)，实现字节流 0 拷贝绝对对齐。

### 3. 强类型枚举的物理映射 (enum)
使用 Teal 原生的 enum 语法：
```teal
local type TradeState = enum "STATE_BUY" "STATE_SELL" end
```
L2C 编译器内置了全局字面量雷达探测器。当您在业务代码中写出 pkt.state = "STATE_BUY" 时，L2C 会瞬间扒掉它的双引号，在 C 底层强行降维成纯数字常量比较 TradeState.STATE_BUY，零字符串比较开销！

---

## 六、 多返回值与 0-GC 指针自动解包
L2C 完美调和了高级脚本语法的优雅与 C 语言系统调用的丑陋。
当您在标准库中调用底层 C 语言的“指针提取函数”时：
```teal
-- 标准库层：吃下底层的苦
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

-- 业务层：享受脚本的甜
local ok, val = SPSC_PopDefault()
```
得益于 L2C 防弹级的 AST 声明解析器，多变量声明 (local a, b = ...) 被完美保留。底层 Clang 的 SROA 优化器会将这些隐藏的栈内存打散进 CPU 寄存器，实现真正的0 逃逸、0 拷贝、多返回值拆包！

---