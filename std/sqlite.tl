-- ==============================================================================
-- Copyright (c) 2026 L2C Architect | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- std/sqlite.tl
-- @l2c_link: sqlite3
-- @l2c_include: sqlite3.h

-- 声明不透明的数据库指针 (底层映射为 void*)
local type sqlite3 = record 
    -- 🔥 声明物理指针魔法，骗过 Teal 静态检查
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
