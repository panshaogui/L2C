-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- std/zmq.tl
-- @l2c_link: zmq
-- @l2c_include: zmq.h

local type zmq_context = record end
local type zmq_socket = record end

local type C_ZMQ = record
    zmq_ctx_new: function(): zmq_context
    zmq_socket: function(ctx: zmq_context, type: integer): zmq_socket
    zmq_connect: function(sk: zmq_socket, endpoint: string): integer
    -- 🔥 补齐 ZMQ 喉管控制函数
    zmq_setsockopt: function(sk: zmq_socket, option: integer, optval: any, optvallen: integer): integer
    zmq_recv: function(sk: zmq_socket, buf: any, len: integer, flags: integer): integer
end
