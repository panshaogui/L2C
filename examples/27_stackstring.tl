--@l2c_import: std/stackstring.tl

print("========== [L2C StackString 0-GC 单元测试] ==========")

-- -------------------------------------------------------------
-- 测试 1: 内存申请与极速初始化
-- -------------------------------------------------------------
local cmd_buf = L2C_Buffer(64)
local cmd_str = L2C_Ref(cmd_buf)

StackStr_init(cmd_str)
print("[Test 1] 初始化完成，初始长度:", StackStr_len(cmd_str))

-- -------------------------------------------------------------
-- 测试 2: 模拟串口逐字节接收 + C 字符串混拼
-- -------------------------------------------------------------
-- 1. 模拟串口中断按字节收到: 'F', 'R', 'E', 'Q', ' '
StackStr_append_char(cmd_str, 64, 70) -- 'F' (ASCII 70)
StackStr_append_char(cmd_str, 64, 82) -- 'R' (ASCII 82)
StackStr_append_char(cmd_str, 64, 69) -- 'E' (ASCII 69)
StackStr_append_char(cmd_str, 64, 81) -- 'Q' (ASCII 81)
StackStr_append_char(cmd_str, 64, 32) -- ' ' (ASCII 32)

-- 2. 拼上指令参数 "433"
StackStr_append_str(cmd_str, 64, "433")

print("[Test 2] 拼接结果:", StackStr_get(cmd_str))
print("[Test 2] 当前长度:", StackStr_len(cmd_str))

-- -------------------------------------------------------------
-- 测试 3: 零 GC 字符串匹配与判断
-- -------------------------------------------------------------
if StackStr_eq(cmd_str, "FREQ 433") then
    print("[Test 3] SUCCESS: 准确命中 'FREQ 433' 指令！")
else
    print("[Test 3] FAILED: 指令匹配失败！")
end

-- -------------------------------------------------------------
-- 测试 4: 复用内存与数字解析 (0-GC 提取参数)
-- -------------------------------------------------------------
-- 清空缓冲区 (重新将长度标为 0)
StackStr_clear(cmd_str)

-- 写入新数字字符串 "915"
StackStr_append_str(cmd_str, 64, "915")

local freq_val = StackStr_to_int(cmd_str)
print("[Test 4] 提取频段整数:", freq_val)

if freq_val == 915 then
    print("[Test 4] SUCCESS: 整数解析正确！")
end

-- -------------------------------------------------------------
-- 测试 5: 栈内存安全溢出测试 (写满 8 字节 Buffer)
-- -------------------------------------------------------------
local tiny_buf = L2C_Buffer(8)
local tiny_str = L2C_Ref(tiny_buf)

StackStr_init(tiny_str)
-- 尝试写入超过 8 字节的文本 "OVERFLOW_TEST"
StackStr_append_str(tiny_str, 8, "OVERFLOW_TEST")

print("[Test 5] 8 字节 Buffer 溢出拦截结果:", StackStr_get(tiny_str))
print("[Test 5] 安全截断后长度:", StackStr_len(tiny_str))

print("======================================================")