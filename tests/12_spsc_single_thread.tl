-- @l2c_import: std/ringbuffer.tl

print("==== 🔬 单线程 SPSC 物理读写极简验证 ====")

local q = SPSC_Queue._cast(L2C_Static("SPSC_Queue"))
local buf_ptr = L2C_Static("[16]integer")
SPSC_Init(q, 16, L2C_PtrAsInt(buf_ptr))

print("1. 正在压入 100 ...")
if SPSC_Push(q, 100) then
    print("   ✅ Push 100 成功!")
else
    print("   ❌ Push 失败!")
end

print("2. 正在压入 200 ...")
if SPSC_Push(q, 200) then
    print("   ✅ Push 200 成功!")
else
    print("   ❌ Push 失败!")
end

print("3. 准备弹出数据...")
local out = IntBox._new()

if SPSC_Pop(q, out) then
    print("   ✅ Pop 1 成功，读出值: ", out.val)
else
    print("   ❌ Pop 1 失败!")
end

if SPSC_Pop(q, out) then
    print("   ✅ Pop 2 成功，读出值: ", out.val)
else
    print("   ❌ Pop 2 失败!")
end

-- EXPECT: ====🔬单线程SPSC物理读写极简验证====1.正在压入100...✅Push100成功!2.正在压入200...✅Push200成功!3.准备弹出数据...✅Pop1成功，读出值:100✅Pop2成功，读出值:200