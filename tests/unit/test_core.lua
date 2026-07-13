-- tests/unit/test_core.lua
local core = require("codegen.core")

print("🧪 [UNIT] 测试 core.lua (大脑与路由) ...")

local codegen = core.new()

-- 1. 测试缩进
codegen.indent_level = 2
assert(codegen:indent() == "    ", "缩进计算错误")
codegen.indent_level = 0

-- 2. 测试 gen() 纯字符串拦截 (C -> c)
assert(codegen:gen("C") == "c", "大写 C 拦截失败")
assert(codegen:gen("Other") == "Other", "普通字符串拦截失败")

-- 3. 测试 gen() 数组自动解包展开
local array_node = { { mock_val = "A" }, { mock_val = "B" } }
-- 临时给 core 挂载一个能处理 mock_val 的假路由，用于验证解包
codegen.gen_mock = function(self, node) return node.mock_val end
for _, v in ipairs(array_node) do v.kind = "mock" end 
assert(codegen:gen(array_node) == "A, B", "数组节点自动展开失败")

-- 4. 测试 gen_statements 底盘
local stmts_node = { { kind = "mock", mock_val = "stmt1" }, { kind = "mock", mock_val = "stmt2" } }
local stmts_res = codegen:gen_statements(stmts_node)
assert(stmts_res == "stmt1\nstmt2", "statements 容器拼接失败")

print("✅ core.lua 测试通过！")
