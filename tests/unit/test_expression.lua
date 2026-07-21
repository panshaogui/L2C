-- tests/unit/test_expression.lua
local expr = require("codegen.expression")

print("🧪 [UNIT] 测试 expression.lua (表达式与内联展开) ...")

local mock_self = {
    gen = function(self, node) return node.mock_val or "mock" end,
    record_registry = {
        ["Order"] = { { name = "price", type = "integer" }, { name = "qty", type = "integer" } }
    }
}

-- 1. 测试常规二元运算与语法抹平 (!= 转 ~=)
local neq_node = { op = { op = "!=" }, e1 = { mock_val = "a" }, e2 = { mock_val = "b" } }
assert(expr.gen_op(mock_self, neq_node) == "a ~= b", "不等于语法抹平失败")

-- 2. 测试数组索引 0-based 对齐 ([x - 1])
local idx_node = { op = { op = "@index" }, e1 = { mock_val = "arr" }, e2 = { mock_val = "i" } }
assert(expr.gen_op(mock_self, idx_node) == "arr[i - 1]", "数组指针物理对齐失败")

-- 3. 测试 字符串拼接打平 (.. 转 ,)
local concat_node = { op = { op = ".." }, e1 = { mock_val = "A" }, e2 = { mock_val = "B" } }
assert(expr.gen_op(mock_self, concat_node) == "A, B", "字符串逗号打平失败")

-- 4. 测试 L2C_Tick_Reset 熔断器拦截
local reset_node = { op = { op = "@funcall" }, e1 = { kind = "variable", tk = "L2C_Tick_Reset" } }
assert(expr.gen_op(mock_self, reset_node) == "L2C_Get_Arena():deallocall()", "内存重置熔断拦截失败")

-- 5. 测试硬核前端内联展开 (带有防御性缺省值)
-- 这里故意不传参数 qty，测试它会不会补默认值 0
local new_node = {
    op = { op = "@funcall" },
    e1 = { kind = "op", op = { op = "." }, e1 = { tk = "Order" }, e2 = { tk = "_new" } },
    e2 = { { mock_val = "100" } } -- 只传了 price = 100
}
local inline_res = expr.gen_op(mock_self, new_node)
assert(inline_res:match("o_ptr.price = 100"), "内联参数 1 赋值失败")
assert(inline_res:match("o_ptr.qty = 0"), "内联防御性缺省值兜底失败！")

-- 6. [TDD 护城河] 测试 L2C_Cast 原生基础类型强转
local cast_node = {
    op = { op = "@funcall" },
    e1 = { kind = "variable", tk = "L2C_Cast" },
    e2 = { { mock_val = "sql_buf" }, { value = '"cstring"' } }
}
assert(expr.gen_op(mock_self, cast_node) == "(@cstring)(sql_buf)", "L2C_Cast 原生强转生成失败")

print("✅ expression.lua 测试通过！")
