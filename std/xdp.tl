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
-- @l2c_include: clib/xdp_parser.h

local type C_NET_TYPE = record
    l2c_net_get_eth_type: function(any): integer
    l2c_ptr_add: function(any, integer): any
    l2c_net_get_ip_proto: function(any): integer
    l2c_net_get_udp_dest: function(any): integer
    l2c_net_get_udp_payload_len: function(any): integer
    -- 映射汇编探针
    l2c_rdtsc: function(): integer
end

local C_NET: C_NET_TYPE

local type C_XDP_TYPE = record
    xdp_start_poll: function(string, any)
    -- 处理网络字节序 (大端序 -> 机器小端序) 的极速内联宏
    ntohs: function(integer): integer
    ntohl: function(integer): integer
end

local C_XDP: C_XDP_TYPE
