-- examples/17_sqlite_logger.tl
-- @l2c_import: std/sqlite.tl
-- @l2c_include: stdio.h

-- 咱们顺手把 C 语言的字符串格式化核武器拉进来！
local type C_LIBC = record
    snprintf: function(any, integer, string, integer, integer): integer
end

print("🚀 L2C SQLite 引擎点火，准备体验 0-GC 极速落盘...")

-- 1. 声明物理指针并连接数据库
-- 🔥 [降维打击] 使用 OOP 魔法，在 C 栈上强制开辟 void* 物理空间，完美通过 Teal 检查
local db = sqlite3._ptr()
local rc = C_SQLITE.sqlite3_open("hft_ticks.db", L2C_Ref(db))

if rc ~= 0 then
    print("❌ 数据库连接失败！")
    return
end
print("✅ 物理连接成功！创建 Ticks 行情表...")

-- 2. 直接向底层丢入硬编码字符串（常量区），0 GC 开销
local create_sql = "CREATE TABLE IF NOT EXISTS ticks (id INTEGER PRIMARY KEY, price INT, qty INT);"
C_SQLITE.sqlite3_exec(db, L2C_Cast(create_sql, "cstring"), nil, nil, nil)

-- 3. 极速写入循环！
print("⏱️ 开始事务，以光速写入 10000 条数据...")
C_SQLITE.sqlite3_exec(db, L2C_Cast("BEGIN TRANSACTION;", "cstring"), nil, nil, nil)

-- 🔥 核心黑魔法：在栈上强开 128 字节纯内存！复用它来构造 SQL，绝不产生 Lua 垃圾！
local sql_buf = L2C_Buffer(128)

for i = 1, 10000 do
    local price = 60000 + i
    local qty = 100
    
    -- 🔥 [物理对齐]：Lua 的 integer 在底层是 64 位 (int64_t)，必须用 C 语言的 %lld 格式化！
    C_LIBC.snprintf(L2C_Ref(sql_buf), 128, "INSERT INTO ticks (price, qty) VALUES (%lld, %lld);", price, qty)
    
    -- 直接把栈内存的物理指针强转为 cstring，塞给 SQLite！
    C_SQLITE.sqlite3_exec(db, L2C_Cast(L2C_Ref(sql_buf), "cstring"), nil, nil, nil)
end

-- 提交事务并关门
C_SQLITE.sqlite3_exec(db, L2C_Cast("COMMIT;", "cstring"), nil, nil, nil)
C_SQLITE.sqlite3_close(db)

print("🏆 10000 条 Tick 数据落盘完毕，请检查当前目录下的 hft_ticks.db！")
