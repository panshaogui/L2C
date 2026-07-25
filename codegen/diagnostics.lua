-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- ==============================================================================
-- L2C 错误码诊断中心 (Diagnostic Center)
-- ==============================================================================

local M = {}

M.CODES = {
    ["E001"] = { title = "动态表分配 (Dynamic Table)", msg = "触发了动态表 (Table) 分配！这会引发严重的堆内存碎片与 GC 灾难。在 L2C 物理域中被严格禁止！请改用 L2C_Buffer 或静态 Record。" },

    ["E002"] = { title = "匿名闭包 (Closure)", msg = "触发了匿名闭包 (Closure)！闭包会隐式捕获外部变量并引发堆内存分配。L2C 严格禁止！请在顶层声明纯静态函数并使用 L2C_FuncPtr 传递指针。" },

    ["E003"] = { title = "泛型迭代器 (Generic Iterator)", msg = "触发了泛型迭代器循环 (ipairs/pairs)！迭代器在底层依赖闭包状态机，会触发 GC。在 L2C 物理域中，请使用最硬核的数值循环 (for i=1, n do) 遍历物理内存！" },

    ["E004"] = { title = "字符串动态拼接 (String Concat)", msg = "触发了运行时字符串拼接 (String Concat)！这会导致隐式内存分配！如果为了打印，请直接使用逗号分隔的多参数 print(a, b)。" },
    
    ["E005"] = { title = "标准库动态字符串 (String Lib)", msg = "触发了标准库动态字符串操作！这会在堆内存中产生 GC 垃圾。请改用 C 风格 buffer 或多参数 print。" },
    
    ["E099"] = { title = "未支持的语法节点 (Unsupported AST Node)", msg = "引擎尚未对其支持。请在 codegen 模块中补充相应的方法！" }
}

-- 统一工业级 Source Map 错误码熔断器
function M.panic(self, err_code, node)
    local diag = M.CODES[err_code] or M.CODES["E099"]
    
    -- 通过 AST 的合并行号 (node.y)，反查 Source Map 找到真实源文件与原行号
    local bundle_y = node and node.y or 0
    local real_loc = self.line_map[bundle_y]
    
    local file_str = real_loc and real_loc.file or (node and node.f) or "unknown"
    local line_str = real_loc and real_loc.line or bundle_y
    local col_str = node and node.x or "?"

    local loc_str = string.format("[%s | 行 %s, 列 %s]", file_str, line_str, col_str)

    print("\n========================================================")
    print(string.format(" [L2C 架构熔断 - %s] %s", err_code, diag.title))
    print("   -> 故障位置: " .. loc_str)
    print("   -> 判决: " .. diag.msg)
    
    if self.bundled_code then
        local dump_file = ".l2c_error_dump.tl"
        local f = io.open(dump_file, "w")
        if f then f:write(self.bundled_code); f:close() end
    end
    print("========================================================\n")
    os.exit(1)
end

return M