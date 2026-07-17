-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- std/xdp.tl
-- @l2c_link: bpf
-- @l2c_link: xdp
-- @l2c_source: clib/xdp_wrapper.c
-- @l2c_include: arpa/inet.h
-- @l2c_include: clib/xdp_wrapper.h

local type C_XDP = record
    xdp_start_poll: function(string, any)
    
    -- 处理网络字节序 (大端序 -> 机器小端序) 的极速内联宏
    ntohs: function(integer): integer
    ntohl: function(integer): integer
end
