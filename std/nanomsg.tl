-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- std/nanomsg.tl
-- @l2c_link: nanomsg
-- @l2c_include: nanomsg/nn.h
-- @l2c_include: nanomsg/pubsub.h

local type C_NN_TYPE = record
    nn_socket: function(integer, integer): integer
    nn_bind: function(integer, string): integer
    nn_connect: function(integer, string): integer
    nn_setsockopt: function(integer, integer, integer, any, integer): integer
    nn_send: function(integer, any, integer, integer): integer
    nn_recv: function(integer, any, integer, integer): integer
    nn_close: function(integer): integer
end

local C_NN: C_NN_TYPE

-- 物理对齐的宏常量 (来自 nn.h)
local NN_AF_SP: integer = 1
local NN_PUB: integer = 32
local NN_SUB: integer = 33
local NN_SUB_SUBSCRIBE: integer = 1
local NN_DONTWAIT: integer = 1

-- ==============================================================================
-- L2C 极简封装：NanoMSG 极速微服务通信 (0-GC Flat API)
-- ==============================================================================

local function NN_Socket_Pub(): integer
    return C_NN.nn_socket(NN_AF_SP, NN_PUB)
end

local function NN_Socket_Sub(): integer
    return C_NN.nn_socket(NN_AF_SP, NN_SUB)
end

local function NN_Bind(sk: integer, endpoint: string): boolean
    return C_NN.nn_bind(sk, endpoint) >= 0
end

local function NN_Connect(sk: integer, endpoint: string): boolean
    return C_NN.nn_connect(sk, endpoint) >= 0
end

-- 彻底消灭心智负担：封装 1 字节空内存订阅过滤器的 Hack
local function NN_Subscribe_All(sk: integer)
    local empty_filter = L2C_Buffer(1)
    C_NN.nn_setsockopt(sk, NN_SUB, NN_SUB_SUBSCRIBE, L2C_Ref(empty_filter), 0)
end

local function NN_Send(sk: integer, buf_ptr: any, len: integer): integer
    return C_NN.nn_send(sk, buf_ptr, len, 0)
end

local function NN_Recv(sk: integer, buf_ptr: any, len: integer): integer
    return C_NN.nn_recv(sk, buf_ptr, len, 0)
end