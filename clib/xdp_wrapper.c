#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <net/if.h>
#include <sys/resource.h>
#include <bpf/bpf.h>
#include <xdp/xsk.h>
#include <linux/if_link.h>
#include <poll.h> // 🔥 新增：引入 poll 唤醒机制

#define NUM_FRAMES 4096
#define FRAME_SIZE XSK_UMEM__DEFAULT_FRAME_SIZE
#define BATCH_SIZE 64

// 暴露给 L2C 的核心入口：传入网卡名和 Lua 回调函数指针
void xdp_start_poll(const char *ifname, void (*lua_callback)(void* packet_ptr, int len)) {
    struct rlimit r = {RLIM_INFINITY, RLIM_INFINITY};
    if (setrlimit(RLIMIT_MEMLOCK, &r)) { perror("setrlimit 失败"); return; }

    void *umem_area = NULL;
    if (posix_memalign(&umem_area, getpagesize(), NUM_FRAMES * FRAME_SIZE)) { perror("posix_memalign 失败"); return; }

    struct xsk_ring_prod fill_ring;
    struct xsk_ring_cons comp_ring;
    struct xsk_umem *umem;
    struct xsk_umem_config umem_cfg = { .fill_size = 2048, .comp_size = 2048, .frame_size = FRAME_SIZE, .frame_headroom = XSK_UMEM__DEFAULT_FRAME_HEADROOM };

    if (xsk_umem__create(&umem, umem_area, NUM_FRAMES * FRAME_SIZE, &fill_ring, &comp_ring, &umem_cfg)) { return; }

    // 🔥 刚刚被我不小心切掉的 4 行生死攸关的声明，全在这里了！
    struct xsk_ring_cons rx_ring;
    struct xsk_ring_prod tx_ring;
    struct xsk_socket *xsk;
    // 🔥 [物理降维：强制 SKB 兼容模式]
    // 既然普通网卡驱动不支持 Native XDP，我们就强行呼叫 Linux 内核的 Generic XDP (SKB 模式)
    // 配合 XDP_COPY，强迫内核为我们做一次内存接力，保证在任何普通网卡 (enp2s0) 上绝对能跑通！

    /*
    struct xsk_socket_config xsk_cfg = { 
        .rx_size = 2048, 
        .tx_size = 2048, 
        .xdp_flags = XDP_FLAGS_SKB_MODE,             // 强制走内核通用层
        .bind_flags = XDP_USE_NEED_WAKEUP | XDP_COPY // 强制兼容拷贝模式
    };

    */

    struct xsk_socket_config xsk_cfg = { .rx_size = 2048, .tx_size = 2048, .xdp_flags = 0, .bind_flags = XDP_USE_NEED_WAKEUP };

    if (xsk_socket__create(&xsk, ifname, 0, umem, &rx_ring, &tx_ring, &xsk_cfg)) { perror("xsk_socket__create 失败"); return; }
    
    // 🚀 预填充 fill_ring，告诉网卡：这些内存地址你可以用来写数据！
    // 🔥 [致命 Bug 修复]：严格对齐 umem_cfg.fill_size 的 2048 容量！
    uint32_t idx_fill;
    uint32_t fill_qty = 2048; 
    if (xsk_ring_prod__reserve(&fill_ring, fill_qty, &idx_fill) != fill_qty) {
        fprintf(stderr, "❌ 严重错误：无法将 UMEM 内存块压入 Fill Ring 队列！内核拒绝了请求！\n");
        return;
    }
    for (uint32_t i = 0; i < fill_qty; i++) {
        *xsk_ring_prod__fill_addr(&fill_ring, idx_fill++) = i * FRAME_SIZE;
    }
    xsk_ring_prod__submit(&fill_ring, fill_qty);

    printf("🚀 [XDP C-Wrapper] AF_XDP 极速轮询引擎点火！物理 DMA 管道已接通...\n");

    // 🔥 新增：配置 pollfd 用于唤醒内核
    struct pollfd fds[1];
    fds[0].fd = xsk_socket__fd(xsk);
    fds[0].events = POLLIN;

    // ⚡ 死循环极致轮询 (Poll)
    while (1) {
        // 🔥 新增：当内核需要唤醒时，通过 poll 踢一脚内核 (防止 veth 饿死)
        if (xsk_ring_prod__needs_wakeup(&fill_ring)) {
            poll(fds, 1, 10); 
        }

        uint32_t idx_rx;
        uint32_t rcvd = xsk_ring_cons__peek(&rx_ring, BATCH_SIZE, &idx_rx);
        if (!rcvd) continue; 

        uint32_t rx_start = idx_rx;
        for (uint32_t i = 0; i < rcvd; i++) {
            const struct xdp_desc *desc = xsk_ring_cons__rx_desc(&rx_ring, idx_rx++);
            // 物理偏移计算：原始基址 + 网卡偏移量
            void *pkt_ptr = (void *)((char *)umem_area + desc->addr);
            
            // 🎯 【高潮时刻】调用 L2C 回调，0 纳秒延迟解构数据包！
            lua_callback(pkt_ptr, desc->len);
        }
        xsk_ring_cons__release(&rx_ring, rcvd);

        // ♻️ 回收站机制：把刚刚用完的内存地址塞回 fill_ring 循环利用，绝对 0 分配！
        uint32_t idx_fq;
        if (xsk_ring_prod__reserve(&fill_ring, rcvd, &idx_fq) == rcvd) {
            for (uint32_t i = 0; i < rcvd; i++) {
                *xsk_ring_prod__fill_addr(&fill_ring, idx_fq++) = xsk_ring_cons__rx_desc(&rx_ring, rx_start + i)->addr;
            }
            xsk_ring_prod__submit(&fill_ring, rcvd);
        }
    }
}
