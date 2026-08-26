-- tests/fail_07_untyped_nil.tl
-- EXPECT_FAIL: Type Errors

print("试图进行跨维度的非法类型赋值...")

-- 将字符串赋值给整数标量，Teal 会瞬间拔枪击毙！
local ptr: integer = "hello L2C"
print(ptr)