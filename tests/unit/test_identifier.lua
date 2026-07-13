-- tests/unit/test_identifier.lua
local ident = require("codegen.identifier")

print("🧪 [UNIT] 测试 identifier.lua (符号与 FFI 伪装) ...")

local mock_self = {
    ffi_typeids = { [999] = true } -- 假设 999 是记录在白皮书里的 FFI 类型
}

-- 1. 测试 gen_variable 拦截大写 C
assert(ident.gen_variable(mock_self, { tk = "C" }) == "c", "gen_variable 漏掉了 FFI 降维打击")
assert(ident.gen_variable(mock_self, { tk = "tick" }) == "tick", "普通变量被误杀")

-- 2. 测试 gen_identifier 的 typeid FFI 白名单检验
assert(ident.gen_identifier(mock_self, { tk = "C", typeid = 999 }) == "c", "gen_identifier 漏掉了白皮书验证")
assert(ident.gen_identifier(mock_self, { tk = "Normal", typeid = 123 }) == "Normal", "普通标识符被误杀")

-- 3. 测试参数强类型生成
local arg_node = {
    tk = "msg",
    argtype = { names = { "cstring" } }
}
assert(ident.gen_argument(mock_self, arg_node) == "msg: cstring", "参数类型映射失败")

print("✅ identifier.lua 测试通过！")
