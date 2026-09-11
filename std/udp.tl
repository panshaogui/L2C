-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- std/udp.tl
-- L2C 0-GC 极速 UDP 战术网关

-- 物理挂载 C 源码
-- @l2c_source: clib/mcu/esp32_udp.c

local type C_UDP = record
    -- [修复] data 改为 any，支持纯内存指针直传
    l2c_udp_send: function(string, integer, any, integer)
    
    -- [新增] 服务端探针
    l2c_udp_server_init: function(integer)
    l2c_udp_pop_cmd: function(any, integer): integer
end

-- ==========================================================
-- 对外导出的 0-GC 战术接口
-- ==========================================================

local function UDP_send(ip: string, port: integer, data: any, len: integer)
    C_UDP.l2c_udp_send(ip, port, data, len)
end

local function UDP_server_init(port: integer)
    C_UDP.l2c_udp_server_init(port)
end

-- 直接将取出的命令灌入 StackString 缓冲区
local function UDP_pop_cmd(str_ptr: any, max_len: integer): boolean
    return C_UDP.l2c_udp_pop_cmd(str_ptr, max_len) == 1
end