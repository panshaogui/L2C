-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- std/nanomsg.tl
-- @l2c_link: nanomsg
-- @l2c_include: nanomsg/nn.h
-- @l2c_include: nanomsg/pubsub.h

local type C_NN = record
    nn_socket: function(integer, integer): integer
    nn_bind: function(integer, string): integer
    nn_connect: function(integer, string): integer
    nn_setsockopt: function(integer, integer, integer, any, integer): integer
    nn_send: function(integer, any, integer, integer): integer
    nn_recv: function(integer, any, integer, integer): integer
    nn_close: function(integer): integer
end

-- 物理对齐的宏常量 (来自 nn.h)
local NN_AF_SP: integer = 1
local NN_PUB: integer = 32
local NN_SUB: integer = 33
local NN_SUB_SUBSCRIBE: integer = 1
local NN_DONTWAIT: integer = 1
