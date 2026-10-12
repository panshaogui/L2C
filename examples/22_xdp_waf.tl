-- examples/22_xdp_waf.tl
require "std.xdp"

-- [防爬虫黑科技]：0-GC 极速 IP 频率计数器
-- 我们在物理栈外开辟一块连续内存，用来统计每个 IP 的发包频率
-- 假设我们用一个最简单的 Hash 数组 (例如 65536 大小，用 IP 的低 16 位做 Hash)
local ip_hash_table = L2C_IntegerArray(65536) 

--【核心修复：提前提取物理指针，转化为极致的整数游标！】
-- L2C_Ref 提取数组内存首地址，L2C_PtrAsInt 坍缩为指针整数。绝对安全！
local hash_table_ptr = L2C_PtrAsInt(L2C_Ref(ip_hash_table))

local function on_packet_received(raw_ptr: any, len: integer)
    if len < 54 then return end

    print(" [L2C-WAF] 回调成功！捕获物理报文 | 长度: ", len)

    local proto_type = C_NET.l2c_net_get_eth_type(raw_ptr)
    --【核心侦察：打印它到底是什么协议！】
    print(" [L2C-WAF] 解析以太网帧... ProtoType: ", proto_type)

    if proto_type == 0x0800 then 
        local ip_ptr = C_NET.l2c_ptr_add(raw_ptr, 14)
        local ip_proto = C_NET.l2c_net_get_ip_proto(ip_ptr)
        
        --【新增：把 IP 协议号打出来！】
        print(" [L2C-WAF] 发现 IPv4... IP_Proto: ", ip_proto)

        if ip_proto == 6 then 
            local tcp_ptr = C_NET.l2c_ptr_add(ip_ptr, 20)
            
            local src_ip = C_NET.l2c_net_get_src_ip(ip_ptr)
            local dest_port = C_NET.l2c_net_get_tcp_dest(tcp_ptr)

            if dest_port == 80 or dest_port == 443 then
                local hash_idx = src_ip & 0xFFFF 
                
                --【核心修复：直接使用刚刚提取出的整数游标！】
                local hits = L2C_ReadArray(hash_table_ptr, hash_idx) + 1
                L2C_WriteArray(hash_table_ptr, hash_idx, hits)

                if hits > 5 then
                    -- 打印罪证
                    -- 【修复：IP 打印需要格式化，不能直接打整个大端整数】
                    local ip1 = src_ip & 255
                    local ip2 = (src_ip >> 8) & 255
                    local ip3 = (src_ip >> 16) & 255
                    local ip4 = (src_ip >> 24) & 255
                    print(" [L2C 熔断系统] 发现致命攻击！封杀 IP:", ip1, ".", ip2, ".", ip3, ".", ip4)
                    
                    C_NET.l2c_net_block_ip(src_ip)
                    print(" [L2C 熔断系统] 该 IP 已被网卡驱动物理锁死！")
                end
            end
        end
    end
end

print(" L2C AF_XDP (防爬虫 WAF 引擎) 启动！")
C_XDP.xdp_start_poll("veth-rx", L2C_FuncPtr(on_packet_received)) -- 填你真实的服务器网卡名