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

## 三、 编译链路 (The Pipeline)
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

## 五、 L2C 在现代编译流水线中的位置

要真正理解 L2C 为什么能做到“写起来像脚本，跑起来像裸机汇编”，我们必须把它放到现代编译原理（LLVM Architecture）的标准流水线中去审视。

L2C 并不是一个从零开始造轮子的“全栈编译器”。它的定位是极其聪明的 **“源到源转译器 (Source-to-Source Compiler) 兼 中端优化拦截网 (Middle-end Warden)”**。

### 🌊 L2C 完整的四大物理生命周期

#### 1. 前端分析 (Frontend) —— 借力 Teal 护城河

*   **传统编译器职责**：词法分析 (Lexing) -> 语法分析 (Parsing) -> 类型检查 (Type Checking)。
*   **L2C 的做法**：直接剥夺 `tl.lua` (Teal 编译器) 的前端能力。利用它强大的静态类型推导，在第一步就把诸如“把字符串赋给整数”、“调用不存在的方法”这种低级错误斩杀。

#### 2. 中端门控与重塑 (Middle-end / L2C 本体) —— 真正的灵魂所在

这是 `l2c_bin` 最核心的战场。在拿到 AST（抽象语法树）后，L2C 执行了超越常规编译器的**“物理域降维审查”**：

*   **0-GC 语义安检 (Feature Gate)**：拦截动态表 `{}`、匿名闭包 `function()`、泛型迭代器 `forin`。只要触发，立刻利用 **Source Map (源码映射表)** 报出类似 `[E001]` 的 Rust 风格极客错误。
*   **宏展开与降维 (Intrinsics Expansion)**：遇到 `L2C_Tick_Reset`，瞬间展开为 `my_arenas[L2C_GET_CORE_ID()]:deallocall()`；遇到 `L2C_Static`，直接翻译成 `.bss` 段的静态 C 变量声明。
*   **硬件兵工厂 (Hardware Forge)**：根据业务代码里的 `@l2c_import`，动态向目标注入不同芯片（Pico/ESP32）的纯 C 汇编宏。

#### 3. IR 代码发射 (IR Emitter) —— 雇佣 Nelua

*   **传统编译器职责**：生成 LLVM IR 或直接发射汇编。
*   **L2C 的做法**：L2C 把修改完毕、且完全符合 0-GC 规范的 AST 字符串，通过命令行喂给 `nelua`。此时的 Nelua 仅仅被当作一个**“C 语言排版与打字机”**。它吐出极其规范的、带有 C 结构体的 `native_app.c` 源码。

#### 4. 机器码生成与链接 (Backend) —— 交付给操作系统 (Clang/GCC)

*   **L2C 隐形债账本**：在调度 Clang 之前，L2C 的 `builder.lua` 会查询账本，自动补齐 `-lstdc++`, `-lsodium` 等跨平台静态债。
*   **极限压榨**：Nelua 拉起 Clang，强制注入 `-O3 -flto -march=native` 硬件极限优化参数。Clang 会将我们在兵工厂里手搓的 C 宏彻底打碎，内联镶嵌到业务循环中，最终生成 30KB 左右的极致单片机固件或宿主机二进制。

---

### 🔬 从 `local a = 1 + 1` 到硅片机器码

#### 🌌 阶段 1：Teal 前端宇宙（思想域的诞生）

1. **词法分析 (Lexing)**：Teal 的解析器扫描文本，把它切碎成 Token 流：`[local]`, `[a]`, `[=]`, `[1]`, `[+]`, `[1]`。

2. **语法分析 (Parsing)**：Teal 把这些碎片组装成一棵 **AST（抽象语法树）**。

   * 它识别出这是一个 `local_declaration` 节点。
   * 左边是 `variable` 节点 `a`。
   * 右边是一个 `op` 节点，操作符是 `+`，左右子节点都是 `literal_number` 1。

3. **类型推断 (Type Checking)**：Teal 发现右边是两个整数相加，于是**在编译期给变量 `a` 打上了一个强类型烙印：`integer`**。

#### 🛡️ 阶段 2：L2C 中端安检（0-GC 纪律审查与转译）

1. **AST 门控 (Feature Gate)**：L2C 大脑（`codegen/core.lua`）接过这棵 AST 树。它核对黑名单：“这里面有没有 `table`？有没有 `function` 闭包？”。发现只有基础运算，安检放行。

2. **IR 文本发射 (Transpilation)**：L2C 开始遍历这棵树，调用 `gen_op`。
   * 遇到 `+` 节点，翻译成文本 `"1 + 1"`。
   * 遇到 `local` 节点，翻译成带类型的 Nelua 文本：`local a: integer = 1 + 1`。

#### ⚙️ 阶段 3：Nelua C-Emitter（过渡到 C 宇宙）

1. **隐式类型映射**：Nelua 编译器接管了这段中间文本。它看到 `integer`，将 `integer` 映射为 C 语言等宽整数（通常是 64 位的 `ptrdiff_t` 或 `int64_t`）。

2. **C 代码生成**：Nelua 在内存中将这段逻辑翻译成原汁原味的 ANSI C 源码。
   ```c
   // 生成的 C 代码
   int64_t a = 1 + 1;
   ```

#### 🔨 阶段 4：Clang / GCC 后端（物理域的重锤）

这才是真正的“炼丹炉”！当 L2C 拿着这段 C 源码，拉起：Nelua 让它带着 `-O3 -march=native -flto` 参数唤醒 Clang 时，魔法发生了：

1. **常量折叠 (Constant Folding)**：
   Clang 的优化器看着 `int64_t a = 1 + 1;`，它笑了。Clang 会在编译期直接帮您把 1+1 算完！代码瞬间变成了 `int64_t a = 2;`。

2. **死代码消除 (Dead Code Elimination, DCE)**：
   Clang 接着往下看，发现您算完 `a` 之后，既没有 `print(a)`，也没有把它塞进 `SPSC_Queue`，甚至没用作返回值。Clang 的激进优化器会毫不留情地把 `int64_t a = 2;` **彻底删掉！** 
   是的，如果您只写了 `1+1`，它在最终的二进制里**连一行汇编指令都不会产生**！

3. **指令集选择 (Instruction Selection)**：
   假设您把 `a` 返回出去了，逃过了死代码消除。Clang 会根据您指定的 `--target=pico`（ARM Cortex-M0+），选择生成对应的汇编指令（比如 `MOVS R0, #2`）。

#### 📦 阶段 5：链接期优化 (Link-Time Optimization, LTO)

1. **跨边界融合**：如果这个 `1 + 1` 发生在我们之前用 C++ 写的胶水库，或者 ZMQ 库内部。因为我们开启了 `-flto`，链接器会把不同的 `.o` 目标文件强行打碎，在全项目级别再次进行内联（Inlining）和折叠优化。
2. **生成机器码 (Machine Code)**：最终，链接器把汇编指令变成了 `0x00 0x1F...` 这种只有 CPU 硅片能读懂的高低电平二进制流，封装进了 `.uf2` 或 `.elf` 文件中。

---
