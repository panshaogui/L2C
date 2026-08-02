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
