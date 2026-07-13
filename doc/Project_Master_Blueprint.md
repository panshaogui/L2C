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
