-- examples/17_sqlite_logger.tl
-- @l2c_import: std/sqlite.tl
-- @l2c_include: stdio.h

local type C_LIBC = record snprintf: function(any, integer, string, integer): integer end

print(" L2C SQLite 引擎点火...")
-- 极其舒适：一行代码搞定双重指针初始化！
local db = SQLite_Open("hft_ticks.db")

SQLite_Exec(db, "CREATE TABLE IF NOT EXISTS ticks (id INTEGER PRIMARY KEY, price INT, qty INT);")
SQLite_Exec(db, "BEGIN TRANSACTION;")

local sql_buf = L2C_Buffer(128)
for i = 1, 10000 do
    local price = 60000 + i
    C_LIBC.snprintf(L2C_Ref(sql_buf), 128, "INSERT INTO ticks (price, qty) VALUES (%lld, 100);", price)
    SQLite_ExecBuffer(db, L2C_Ref(sql_buf))
end

SQLite_Exec(db, "COMMIT;")
SQLite_Close(db)
print(" 10000 条 Tick 数据落盘完毕！")