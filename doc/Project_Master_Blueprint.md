# 🗺️ L2C Compiler - Project Master Blueprint (v1.0)

## 一、 核心哲学 (Core Philosophy)
*   **0-GC / 物理内存分配**：彻底物理阉割 Lua 垃圾回收。系统内存模型仅包含：
    *   **栈内存 (Stack)**：`L2C_Buffer(size)` 宏生成定长 C 数组。
    *   **Tick 级内存池 (Arena)**：`10MB` 容量，`L2C_Tick_Reset()` 触发 `O(1)` 极速重置。
*   **零开销抽象 (Zero-Cost Abstraction)**：所有的高层面向对象写法（如 `Order._new`）均在编译期被**强制前端内联展开**为纯指针位移。
*   **AOT 静态强类型**：依赖 Teal 进行 AST 类型推断，拒绝运行期 `Any`，遇到 FFI 自动降维为 `void* (pointer)`。

## 二、 物理文件系统拓扑 (Architecture Topology)
```text
L2C-Project/
├── l2c.lua                  # 🌟 编译器主入口 (Unity Build 拼接器 + Clang 调度器)
│   └── 包含 STD_DEBT_REGISTRY (静态链接隐形债自动清偿)
│   └── 包含 L2C Intrinsics (全局魔法宏自动注入)
├── codegen/        # 🧠 AST 翻译引擎 (核心 1大脑 + 5器官)
│   ├── core.lua             # 调度器大脑: self:gen() 路由中心
│   ├── declaration.lua      # 声明器官: FFI C 命名空间隔离 / Record 注册表写入
│   ├── flow.lua             # 控制流器官: if / for / while / return
│   ├── expression.lua       # 表达式器官: _new 内联 / L2C_Cast 零拷贝强转
│   ├── literal.lua          # 字面量器官: Stack Array `(@[]int)` 映射
│   └── identifier.lua       # 符号器官: `C_XXX` 降维打击映射至小写 `c`
├── tests/unit/              # 🧪 白盒测试套件 (Mock self 隔离测试)
├── std/                     # 📦 标准库 (VTable/模块化设计，通过 @l2c_import 拼装)
│   ├── time.tl              # CLOCK_REALTIME 纳秒时钟
│   └── zmq.tl               # ZMQ 高频网关 FFI 封装
└── test_runner.lua          # 🚥 TDD 集成测试引擎
```

## 三、 黑科技编译链路 (The Pipeline)
1.  **Unity Build 物理拼接**：扫描 `-- @l2c_import`，将依赖文本原地展开合并。
2.  **AST 提取**：交由 `teal.process_string` 生成带类型签名的 AST 树。
3.  **L2C 核心转译 (Codegen)**：
    *   遍历 AST，通过 `Visitor` 模式派发至 5 个器官。
    *   遇到 FFI：将 `C_ZMQ` 声明转化为 `<cimport, nodecl>` 的 C 符号。
    *   遇到内存分配：执行缺省值安全兜底，生成 `(do ... in ... end)` 内联宏。
4.  **Nelua 极速转译**：将生成的 `.nelua` 文件转为纯 C 代码。
5.  **Clang 硬件级优化**：读取 `@l2c_link`，执行隐形债偿还，并加注 Apple Silicon 特有路径，通过 `-O3 -march=native -flto` 压制出极限二进制。

---

## 四、 L2C架构原理：

 **L2C 的三大架构铁律与设计哲学**

### 铁律一：双重宇宙，物理隔离 (The Two-Universe Isolation)
L2C 彻底抛弃了传统编译器“大包大揽”的臃肿模式，它在架构上被严格切分成了互不越界的两个宇宙：

*   **🌌 上层宇宙（前端 - 思想域）：`l2c_bin` 本体**
    *   **成分**：Lua 5.4 虚拟机 + Teal 静态类型检查器 + L2C Unity Build 引擎。
    *   **使命**：负责一切“高层抽象”和“开发体验”。它处理模块拼接（`@l2c_import`）、执行宏内联展开（`L2C_Cast`、`_new`）、接管 C 语言的隐藏账单（`STD_DEBT_REGISTRY`）。
    *   **特点**：极度轻量（仅 700KB）、绝对自包含。它可以跑在地球上任何一台机器上，**只负责把 Teal 剧本，物理降维成最纯正的 ANSI C 源码**。

*   **🌋 下层宇宙（后端 - 物理域）：底层基建环境**
    *   **成分**：Nelua（C代码生成器）+ Clang/GCC + 操作系统头文件。
    *   **使命**：负责与真实的硅片、寄存器和网卡肉搏。
    *   **特点**：极度沉重、极度依赖宿主环境（比如 Mac 的 Homebrew，Linux 的 Glibc/Musl）。

### 铁律二：“纯 C 源码”是绝对的停火区 (The ANSI C DMZ)

在前端和后端这两个宇宙之间，唯一的通信协议，就是**“纯正的 C 源码文件 (`.c`)”**。

*   L2C 不负责生成二进制，它只负责把思想翻译成 C。
*   为什么不把 Nelua 包进去？因为 **“破窗效应”**。包了 Nelua，就必须包 Clang；包了 Clang，就必须包 Linux/Mac 的内核头文件（`libc`）。一旦那么做，L2C 就会从一把 700KB 的精巧手术刀，膨胀成一个高达几 GB 的垃圾堆。
*   让 L2C 在生成 `.c` 之后就优雅地退出，这是对软件工程模块化最极致的尊崇。

### 铁律三：Docker 炼丹炉填补物理断层 (The Docker Forges)
既然 L2C 本体不带沉重的后端，那怎么实现开箱即用的跨平台编译？
答案是：**“环境即代码 (Environment as Code)”**。

我们把交叉编译环境、第三方依赖、复杂的 Makefile，全部封印在不同的 Docker 容器（炼丹炉）里：

1.  **`l2c-musl-forge`**：专门负责 Linux 全静态云端二进制（Musl libc 炼丹炉）。
2.  **`l2c-pico-forge`**：专门负责树莓派单片机（ARM GCC + FreeRTOS 炼丹炉）。
3.  **`l2c-esp32-forge`**：专门负责乐鑫无线芯片（ESP-IDF + Xtensa GCC 炼丹炉）。

---
