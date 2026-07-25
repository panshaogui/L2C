-- tests/fail_04_string_concat.tl
-- EXPECT_FAIL: E004

local prefix = "HW_"
local id = "01"

print("试图在运行时通过 .. 拼接字符串...")

-- 👈 字符串拼接必须熔断！这在 C 里需要隐式 malloc 分配新内存
local full_id = prefix .. id
print(full_id)