// bpf/kernel_killer.c
#include <linux/bpf.h>
#include <linux/if_ether.h>
#include <linux/ip.h>
#include <bpf/bpf_helpers.h>

// 【绝密黑名单】：用户态 L2C 和 eBPF 共享的封杀令
struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __uint(max_entries, 65536); 
    __type(key, __u32);         
    __type(value, __u8);        
} blacklist_map SEC(".maps");

// 【新增：AF_XDP 专属快递通道】！好包全部通过这个地图送给 L2C！
struct {
    __uint(type, BPF_MAP_TYPE_XSKMAP);
    __uint(max_entries, 64);
    __type(key, int);
    __type(value, int);
} xsks_map SEC(".maps");

SEC("xdp")
int xdp_killer_prog(struct xdp_md *ctx) {
    void *data_end = (void *)(long)ctx->data_end;
    void *data = (void *)(long)ctx->data;

    struct ethhdr *eth = data;
    if (data + sizeof(*eth) > data_end) goto pass_to_l2c;
    if (eth->h_proto != __constant_htons(ETH_P_IP)) goto pass_to_l2c;

    struct iphdr *ip = data + sizeof(*eth);
    if ((void*)(ip + 1) > data_end) goto pass_to_l2c;

    __u32 src_ip = ip->saddr;

    // 【物理斩首】
    __u8 *is_blocked = bpf_map_lookup_elem(&blacklist_map, &src_ip);
    if (is_blocked && *is_blocked == 1) {
        return XDP_DROP; // 爬虫直接在网卡硬件上灰飞烟灭！
    }

pass_to_l2c:
    // 【物理押送】：正常的包，直接 Bypass 内核，通过高速通道扔给 L2C 引擎！
    return bpf_redirect_map(&xsks_map, ctx->rx_queue_index, 0);
}

char _license[] SEC("license") = "GPL";