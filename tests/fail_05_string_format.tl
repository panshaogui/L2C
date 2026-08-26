-- tests/fail_05_string_format.tl
-- EXPECT_FAIL: E005

local val = 42
print("试图调用 string.format 动态创建字符串...")

-- 严禁产生动态 string 对象的库函数，必须用 C 的 sprintf 或强类型转换代替
local msg = string.format("sensor_val: %d", val)
print(msg)