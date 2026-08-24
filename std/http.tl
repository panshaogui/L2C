-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- ==============================================================================
-- L2C 极简标准库：HTTP 物理数据提取器
-- ==============================================================================
-- @l2c_link: curl
-- @l2c_source: clib/http_fetcher.c
-- @l2c_include: clib/http_fetcher.h

local type C_HTTP = record
    http_get: function(string, any, integer): integer
end

-- 极简封装，向业务层屏蔽底层 C 函数
global function HTTP_Get(url: string, buf_ptr: any, max_len: integer): integer
    return C_HTTP.http_get(url, buf_ptr, max_len)
end