// ==============================================================================
// Copyright (c) 2026 Panshaogui | MIT License
// L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
// ==============================================================================

#ifndef XDP_PARSER_H
#define XDP_PARSER_H

#include <stdint.h>
#include <arpa/inet.h>

#pragma pack(push, 1)
typedef struct {
    uint8_t  dest_mac[6];
    uint8_t  src_mac[6];
    uint16_t eth_type;
} l2c_eth_hdr_t;

typedef struct {
    uint8_t  ihl_version;
    uint8_t  tos;
    uint16_t tot_len;
    uint16_t id;
    uint16_t frag_off;
    uint8_t  ttl;
    uint8_t  protocol;
    uint16_t check;
    uint32_t saddr;
    uint32_t daddr;
} l2c_ip_hdr_t;

typedef struct {
    uint16_t source;
    uint16_t dest;
    uint16_t len;
    uint16_t check;
} l2c_udp_hdr_t;

typedef struct {
    uint16_t source;
    uint16_t dest;
    uint32_t seq;
    uint32_t ack_seq;
    uint8_t  res1:4, doff:4;
    uint8_t  flags; // SYN, ACK, FIN, RST 等标志位
    uint16_t window;
    uint16_t check;
    uint16_t urg_ptr;
} l2c_tcp_hdr_t;
#pragma pack(pop)

static inline uint16_t l2c_net_get_eth_type(void* ptr) {
    return ntohs(((l2c_eth_hdr_t*)ptr)->eth_type);
}

static inline void* l2c_ptr_add(void* base, int offset) {
    return (void*)((char*)base + offset);
}

static inline uint16_t l2c_net_get_udp_dest(void* udp_ptr) {
    return ntohs(((l2c_udp_hdr_t*)udp_ptr)->dest);
}

static inline uint16_t l2c_net_get_udp_payload_len(void* udp_ptr) {
    return ntohs(((l2c_udp_hdr_t*)udp_ptr)->len) - 8;
}

// 提取 TCP Header 长度（字节）
static inline uint8_t l2c_net_get_tcp_header_len(void* tcp_ptr) {
    return ((l2c_tcp_hdr_t*)tcp_ptr)->doff * 4;
}

/*

static inline uint8_t l2c_net_get_ip_proto(void* ip_ptr) {
    return ((l2c_ip_hdr_t*)ip_ptr)->protocol;
}

// 提取 TCP 目标端口 (需要 ntohs)
static inline uint16_t l2c_net_get_tcp_dest(void* tcp_ptr) {
    return ntohs(((l2c_tcp_hdr_t*)tcp_ptr)->dest);
}

// 提取 TCP 源端口 (需要 ntohs)
static inline uint16_t l2c_net_get_tcp_src(void* tcp_ptr) {
    return ntohs(((l2c_tcp_hdr_t*)tcp_ptr)->source);
}

// 提取 IPv4 源 IP 地址 (直接返回原始网络字节序的 32 位整数，极其适合做 Hash 和匹配)
static inline uint32_t l2c_net_get_src_ip(void* ip_ptr) {
    return ((l2c_ip_hdr_t*)ip_ptr)->saddr;
}

// 提取 IPv4 目标 IP 地址
static inline uint32_t l2c_net_get_dest_ip(void* ip_ptr) {
    return ((l2c_ip_hdr_t*)ip_ptr)->daddr;
}

*/

// 提取 IPv4 协议号：IP头偏移第 9 字节
static inline uint8_t l2c_net_get_ip_proto(void* ip_ptr) {
    return *((uint8_t*)ip_ptr + 9);
}

// 提取 TCP 目标端口：TCP头偏移第 2 字节 (占2字节，需大小端转换)
static inline uint16_t l2c_net_get_tcp_dest(void* tcp_ptr) {
    return ntohs(*((uint16_t*)((uint8_t*)tcp_ptr + 2)));
}

// 提取 TCP 源端口：TCP头偏移第 0 字节
static inline uint16_t l2c_net_get_tcp_src(void* tcp_ptr) {
    return ntohs(*((uint16_t*)((uint8_t*)tcp_ptr + 0)));
}

// 提取 IPv4 源 IP：IP头偏移第 12 字节
static inline uint32_t l2c_net_get_src_ip(void* ip_ptr) {
    return *((uint32_t*)((uint8_t*)ip_ptr + 12));
}

// 提取 IPv4 目标 IP：IP头偏移第 16 字节
static inline uint32_t l2c_net_get_dest_ip(void* ip_ptr) {
    return *((uint32_t*)((uint8_t*)ip_ptr + 16));
}

// 新增：嵌入式汇编探针，直接读取 CPU 核心跳动周期
static inline uint64_t l2c_rdtsc(void) {
    unsigned int lo, hi;
    // volatile 阻止编译器为了优化而重排此指令
    __asm__ __volatile__ ("rdtsc" : "=a" (lo), "=d" (hi));
    return ((uint64_t)hi << 32) | lo;
}

#endif // XDP_PARSER_H
