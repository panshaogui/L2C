-- tests/fail_03_forin.tl
-- EXPECT_FAIL: E003

print("准备分配合法的物理定长栈数组...")
local arr: {integer} = {10, 20, 30}

print("试图使用导致 GC 的泛型迭代器遍历数组...")

-- 👈 这一行必须引发 L2C 编译器架构熔断，严禁 ipairs/pairs！
for index, value in ipairs(arr) do
    print(value)
end