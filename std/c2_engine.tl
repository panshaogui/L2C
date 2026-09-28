-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- @l2c_source: clib/mcu/esp32_c2_engine.c

local type C_C2 = record
    l2c_c2_msg_push: function(any): integer
    l2c_c2_msg_pop: function(any): integer
    l2c_c2_fleet_update: function(integer): integer
    l2c_c2_fleet_get_active: function(any): integer
end

local function C2_Msg_Push(str_ptr: any): boolean
    return C_C2.l2c_c2_msg_push(str_ptr) == 1
end

local function C2_Msg_Pop(str_ptr: any): boolean
    return C_C2.l2c_c2_msg_pop(str_ptr) == 1
end

local function C2_Fleet_Update(ip: integer): boolean
    return C_C2.l2c_c2_fleet_update(ip) == 1
end

-- 返回当前存活节点的数量，存入 L2C_Buffer (需至少 32 字节容量以容纳 8 个 IP)
local function C2_Fleet_Get_Active(ip_array_buf: any): integer
    return C_C2.l2c_c2_fleet_get_active(ip_array_buf)
end