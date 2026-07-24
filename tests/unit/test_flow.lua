-- tests/unit/test_flow.lua
local flow = require("codegen.flow")

print(" [UNIT] 测试 flow.lua (控制流) ...")

-- 伪造注入的 self 上下文
local mock_self = {
    indent_level = 0,
    indent = function() return "" end,
    gen = function(self, node) return node.mock_val or "" end
}

-- 1. 测试 while 循环
local while_node = { exp = { mock_val = "true" }, body = { mock_val = "print(1)" } }
local while_res = flow.gen_while(mock_self, while_node)
assert(while_res == "while true do\nprint(1)\nend", "While 循环生成失败")

-- 2. 测试 fornum 循环
local for_node = { var = { tk = "i" }, from = { mock_val = "1" }, to = { mock_val = "5" }, body = { mock_val = "sum()" } }
local for_res = flow.gen_fornum(mock_self, for_node)
assert(for_res == "for i = 1, 5 do\nsum()\nend", "For 循环生成失败")

-- 3. 测试带 step 的 fornum
local for_step_node = { var = { tk = "i" }, from = { mock_val = "10" }, to = { mock_val = "1" }, step = { mock_val = "-1" }, body = { mock_val = "sum()" } }
assert(flow.gen_fornum(mock_self, for_step_node) == "for i = 10, 1, -1 do\nsum()\nend", "带步长的 For 循环失败")

-- 4. 测试 if-else 分支
local if_node = {
    if_blocks = {
        { tk = "if", exp = { mock_val = "x>1" }, body = { mock_val = "a()" } },
        { tk = "else", body = { mock_val = "b()" } }
    }
}
local if_res = flow.gen_if(mock_self, if_node)
assert(if_res:match("if x>1 then"), "If 生成失败")
assert(if_res:match("else"), "Else 生成失败")

-- 5. 测试 return
local ret_node = { exps = { mock_val = "x + 1" } }
assert(flow.gen_return(mock_self, ret_node) == "return x + 1", "Return 生成失败")

-- 6. [TDD 护城河] 测试 Teal Compat Polyfill 幽灵垫片的物理切除
local polyfill_node = {
    if_blocks = {
        { tk = "if", exp = { mock_val = "(tonumber((_VERSION or '') : match('[%d.]*$')) or 0) < 5.3" }, body = { mock_val = "poly()" } }
    }
}

local poly_res = flow.gen_if(mock_self, polyfill_node)
-- 断言它必须被安全切除，且必须是合法的 Nelua 注释语法（--），绝不能是 C 语法（/*）
assert(poly_res == "-- L2C: Stripped Teal Compat Polyfill", "幽灵垫片切除失败或注释语法非法")

-- 7. [TDD] 测试 repeat-until 循环 (C 语言 do-while 的等价物)
local repeat_node = { cond = { mock_val = "x>10" }, block = { mock_val = "add()" } }
assert(flow.gen_repeat(mock_self, repeat_node) == "repeat\nadd()\nuntil x>10", "Repeat 循环生成失败")

-- 8. [TDD] 测试 do 作用域块
local do_node = { block = { mock_val = "step()" } }
assert(flow.gen_do(mock_self, do_node) == "do\nstep()\nend", "Do 作用域块生成失败")

-- 9. [TDD] 测试极客底层跳转 (Goto)
local goto_node = { name = "escape_hatch" }
assert(flow.gen_goto(mock_self, goto_node) == "goto escape_hatch", "Goto 指令生成失败")

-- 10. [TDD] 测试跳转标签 (Label)
local label_node = { name = "escape_hatch" }
assert(flow.gen_label(mock_self, label_node) == "::escape_hatch::", "Label 标签生成失败")

print(" flow.lua 测试通过！")
