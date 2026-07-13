# 🚀 L2C (Lua-to-C) 终极极客使用手册

**Transpile Typed Lua directly into 0-GC Native C.**

L2C 并不是一个通用的 Lua 编译器，而是一个专为 **高频交易 (HFT)**、低延迟网关和内核级信号处理打造的 **物理级安全子集**。它将高级脚本语言（Teal）的优雅，以“零开销抽象”的方式，降维编译成压榨硬件极限的纯 C 二进制代码。

⚠️ **警告：阅读使用前必须了解的铁律**
L2C **物理阉割了垃圾回收（GC）**。在这里，没有闭包，没有动态表，没有运行期 `Any`，没有字符串拼接。如果你需要这些，请退回 LuaJIT；如果你渴望获得 **30KB 体积、50万+ msg/s 吞吐量、纳秒级无抖动** 的绝对力量，请继续阅读。

---

## ⚙️ 一、 环境部署与编译构建

L2C 编译器本身已被打包为单文件二进制可执行程序 `l2c_bin`。

### 1. 编译命令
```bash
./l2c_bin <入口文件.tl> [-o <输出二进制名>]
```
执行后，L2C 会自动完成 AST 解析、物理拼接、C 语言转换，并唤醒操作系统的 `Clang` 编译器开启 `-O3 -march=native -flto` 硬件级极限优化。

### 2. Apple Silicon (M系芯片) 自动适配
L2C 编译器内置了针对 Mac M系列芯片的物理寻址雷达。当检测到需要链接 C 库时，会自动挂载 `/opt/homebrew/include` 和 `/opt/homebrew/lib`。

---

## 🧱 二、 Unity Build：跨模块工程组织

在 0-GC 的世界里，传统的 `require` 模块会导致不可控的内存分配。L2C 采用 **Unity Build (物理拼接)** 的方式组织大型工程。

**绝对禁令**：禁止使用 `require` 导入本地模块！
**正确姿势**：在文件顶部使用元注释进行源码级拼接：

```lua
-- @l2c_import: std/zmq.tl
-- @l2c_import: utils/math_ext.tl
```
L2C 在编译期会将依赖文件如 C 语言的 `#include` 一样，在词法作用域内原地平铺展开，彻底消灭模块调用的性能损耗。

---

## 🧠 三、 极速内存管理 (核心语法)

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

## 🔌 四、 C FFI：对话物理世界

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

## 📦 五、 L2C 标准库 (L2C-STD)

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

## 🚫 六、 杂项与语法禁令

*   **字符串拼接禁令**：禁止使用 `a .. b` 进行字符串组合赋值。如果仅仅是为了打印，L2C 编译器提供特权：`print("Price: " .. p)` 会在底层被物理打平为多参数逗号输出 `print("Price: ", p)`，实现 0-GC 打印。
*   **不等于符号**：底层引擎已将 Teal 的 `~=` 与 C 的 `!=` 物理抹平，你在高层写 `~=` 即可。
*   **向下取整除法**：使用 `a // b` 代替 `a / b`，底层将编译为极速的整型汇编指令。

