-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- std/sqlite.tl
-- @l2c_link: sqlite3
-- @l2c_include: sqlite3.h

-- 声明不透明的数据库指针 (底层映射为 void*)
local type sqlite3 = record 
    -- 声明物理指针魔法，骗过 Teal 静态检查
    _ptr: function(): sqlite3
end

local type C_SQLITE = record
    -- int sqlite3_open(const char *filename, sqlite3 **ppDb);
    sqlite3_open: function(string, any): integer
    
    -- int sqlite3_exec(sqlite3*, const char *sql, int (*callback)(void*,int,char**,char**), void *, char **errmsg);
    sqlite3_exec: function(sqlite3, any, any, any, any): integer
    
    sqlite3_close: function(sqlite3): integer
end

-- 导出状态码
local SQLITE_OK: integer = 0

-- ==============================================================================
-- L2C 极简封装：SQLite 零开销存储
-- ==============================================================================

-- 核心优雅：隐藏双重指针解引用，直接返回干净的 db 句柄！
local function SQLite_Open(filename: string): sqlite3
    local db = sqlite3._ptr()
    local rc = C_SQLITE.sqlite3_open(filename, L2C_Ref(db))
    if rc ~= 0 then return nil end
    return db
end

-- 针对常量的执行
local function SQLite_Exec(db: sqlite3, sql: string): integer
    return C_SQLITE.sqlite3_exec(db, L2C_Cast(sql, "cstring"), nil, nil, nil)
end

-- 针对高性能栈内存 (Buffer) 的复用执行
local function SQLite_ExecBuffer(db: sqlite3, sql_buf: any): integer
    return C_SQLITE.sqlite3_exec(db, L2C_Cast(L2C_Ref(sql_buf), "cstring"), nil, nil, nil)
end

local function SQLite_Close(db: sqlite3): integer
    return C_SQLITE.sqlite3_close(db)
end
