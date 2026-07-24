-- tests/unit/test_literal.lua
local literal = require("codegen.literal")

print(" [UNIT] 测试 literal.lua (字面量与连续内存) ...")

local mock_self = {
    gen = function(self, node) return node.mock_val or node.tk or "mock" end
}

-- 1. 测试纯数字与布尔
assert(literal.gen_integer(mock_self, { tk = "42" }) == "42", "整数生成失败")
assert(literal.gen_boolean(mock_self, { tk = "true" }) == "true", "布尔生成失败")
assert(literal.gen_string(mock_self, { value = '"hello"' }) == '"hello"', "字符串生成失败")

-- 2. 测试定长栈数组 (Stack Array)
local array_node = {
    expected = { typename = "array", elements = { typename = "integer" } },
    { kind = "literal_table_item", value = { mock_val = "10" } },
    { kind = "literal_table_item", value = { mock_val = "20" } }
}
assert(literal.gen_literal_table(mock_self, array_node) == "(@[2]integer){10, 20}", "栈数组生成失败")

-- 3. 测试 Record 字面量
local rec_node = {
    expected = { typename = "nominal", names = { "Order" } },
    { kind = "literal_table_item", tk = "price", value = { mock_val = "100" } }
}
assert(literal.gen_literal_table(mock_self, rec_node) == "Order{price = 100}", "Record 字面量生成失败")

print(" literal.lua 测试通过！")
