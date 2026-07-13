-- tests/unit/test_declaration.lua
local decl = require("codegen.declaration")

print("🧪 [UNIT] 测试 declaration.lua (声明与宏) ...")

local mock_self = {
    indent_level = 0,
    indent = function(self) return string.rep("  ", self.indent_level) end,
    gen = function(self, node) return node.mock_val or "mock" end,
    record_registry = {},
    ffi_typeids = {}
}

-- 1. 测试普通局部变量声明
local local_node = { vars = { { tk = "x" } }, exps = { mock_val = "10" } }
assert(decl.gen_local_declaration(mock_self, local_node) == "local x = 10", "局部变量声明失败")

-- 2. 测试 L2C_Buffer 内存强开宏
local buf_node = {
    vars = { { tk = "msg_buf" } },
    exps = { { kind = "op", op = { op = "@funcall" }, e1 = { tk = "L2C_Buffer" }, e2 = { { mock_val = "1024" } } } }
}
assert(decl.gen_local_declaration(mock_self, buf_node) == "local msg_buf: [1024]byte", "L2C_Buffer 宏展开失败")

-- 3. 测试普通 Record 与类型搜集
local record_node = {
    tk = "Order",
    value = { newtype = { def = {
        typename = "record",
        field_order = { "price", "qty" },
        fields = { price = { typename = "integer" }, qty = { typename = "integer" } }
    }}}
}
local rec_res = decl.gen_local_type(mock_self, record_node)
assert(rec_res:match("local Order = @record"), "普通 Record 声明失败")
assert(mock_self.record_registry["Order"][1].name == "price", "注册表登记失效")

-- 4. [TDD 护城河] 测试 Teal Compat Polyfill 幽灵垫片的物理切除
local polyfill_decl_node = { vars = { { tk = "math" } }, exps = { mock_val = "_tl_compat and _tl_compat.math or math" } }
assert(decl.gen_local_declaration(mock_self, polyfill_decl_node) == "-- L2C: Stripped Teal _tl_compat polyfill", "_tl_compat 垫片切除失败")

-- 5. [TDD 护城河] 测试 L2C_NumberArray 栈数组强开宏
local array_macro_node = {
    vars = { { tk = "fft_buf" } },
    exps = { { kind = "op", op = { op = "@funcall" }, e1 = { tk = "L2C_NumberArray" }, e2 = { { mock_val = "256" } } } }
}
assert(decl.gen_local_declaration(mock_self, array_macro_node) == "local fft_buf: [256]number", "L2C_NumberArray 宏展开失败")

print("✅ declaration.lua 测试通过！")
