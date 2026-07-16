-- examples/22_xdp_sniffer.tl
-- @l2c_import: std/xdp.tl
-- @l2c_include: clib/xdp_parser.h

local type C_NET = record
    l2c_net_get_eth_type: function(any): integer
    l2c_ptr_add: function(any, integer): any
    l2c_net_get_ip_proto: function(any): integer
    l2c_net_get_udp_dest: function(any): integer
    l2c_net_get_udp_payload_len: function(any): integer
    -- 🔥 映射汇编探针
    l2c_rdtsc: function(): integer
end

local packet_count = 0

local function on_packet_received(raw_ptr: any, len: integer)
    -- ⏱️ 计时开始：网卡数据刚落在 L2C 回调的这一纳秒！
    local t0 = C_NET.l2c_rdtsc()

    if len < 34 then return end 

    local proto_type = C_NET.l2c_net_get_eth_type(raw_ptr)
    if proto_type == 0x0800 then 
        local ip_ptr = C_NET.l2c_ptr_add(raw_ptr, 14)
        local ip_proto = C_NET.l2c_net_get_ip_proto(ip_ptr)
        
        if ip_proto == 17 then 
            local udp_ptr = C_NET.l2c_ptr_add(ip_ptr, 20)
            local dest_port = C_NET.l2c_net_get_udp_dest(udp_ptr)
            
            if dest_port == 138 or dest_port == 137 then return end
            
            local payload_len = C_NET.l2c_net_get_udp_payload_len(udp_ptr)
            
            -- ⏱️ 计时结束：成功解开以太网、IPv4、UDP 三层伪装！
            local t1 = C_NET.l2c_rdtsc()
            
            packet_count = packet_count + 1
            local cycles = t1 - t0
            print("⚡ [HFT-Bench] UDP 破译完毕! 端口:", dest_port, " | 消耗 CPU 时钟周期:", cycles)
        end
    end
end

print("🚀 L2C AF_XDP (RDTSC 测速版) 启动！")
C_XDP.xdp_start_poll("veth-rx", L2C_FuncPtr(on_packet_received))
