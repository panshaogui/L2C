-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- std/zmq.tl
-- @l2c_link: zmq
-- @l2c_include: zmq.h

local type zmq_context_t = record end
local type zmq_socket_t = record end

local type C_ZMQ = record
    zmq_ctx_new: function(): zmq_context_t
    zmq_socket: function(ctx: zmq_context_t, type: integer): zmq_socket_t
    zmq_connect: function(sk: zmq_socket_t, endpoint: string): integer
    zmq_setsockopt: function(sk: zmq_socket_t, option: integer, optval: any, optvallen: integer): integer
    zmq_recv: function(sk: zmq_socket_t, buf: any, len: integer, flags: integer): integer
end

-- ==============================================================================
-- L2C 极简封装：ZMQ 高频网关 (0-GC Flat API)
-- ==============================================================================

-- 隐藏的 C 宏枚举值
local ZMQ_SUB_TYPE: integer = 2
local ZMQ_SUBSCRIBE_OPT: integer = 6

-- 1. 上下文与 Socket 创建
local function ZMQ_Context(): zmq_context_t
    return C_ZMQ.zmq_ctx_new()
end

local function ZMQ_Socket_Sub(ctx: zmq_context_t): zmq_socket_t
    return C_ZMQ.zmq_socket(ctx, ZMQ_SUB_TYPE)
end

local function ZMQ_Connect(sk: zmq_socket_t, endpoint: string): boolean
    return C_ZMQ.zmq_connect(sk, endpoint) == 0
end

-- 2. 究极心智降维：隐藏 1 字节空内存申请的“魔法 Hack”！
local function ZMQ_Subscribe_All(sk: zmq_socket_t)
    local empty_filter = L2C_Buffer(1)
    C_ZMQ.zmq_setsockopt(sk, ZMQ_SUBSCRIBE_OPT, L2C_Ref(empty_filter), 0)
end

-- 3. 极速接收 (默认 flag=0)
local function ZMQ_Recv(sk: zmq_socket_t, buf_ptr: any, max_len: integer): integer
    return C_ZMQ.zmq_recv(sk, buf_ptr, max_len, 0)
end