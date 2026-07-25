-- tests/fail_01_dynamic_table.tl
-- EXPECT_FAIL: E001

print("准备分配一个恶心的动态表...")

local my_array = {1, 2, 3}

print(my_array[1])