// ==============================================================================
// Copyright (c) 2026 Panshaogui | MIT License
// L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
// ==============================================================================

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <net/if.h>
#include <sys/resource.h>
#include <poll.h>
#include <bpf/bpf.h>
#include <bpf/libbpf.h>
#include <xdp/xsk.h>
#include <linux/if_link.h>

#define NUM_FRAMES 4096
#define FRAME_SIZE XSK_UMEM__DEFAULT_FRAME_SIZE
#define BATCH_SIZE 64

static struct bpf_object *g_bpf_obj = NULL;
static int g_blacklist_map_fd = -1;
static int g_xsks_map_fd = -1;
static int g_ifindex = -1;
static struct bpf_link *g_bpf_link = NULL;

// 物理网卡卸载与安全清理钩子
static void cleanup_bpf(void) {
    // 防御性清理：必须使用 !libbpf_get_error 校验指针有效性，防止销毁野指针引发段错误
    if (g_bpf_link && !libbpf_get_error(g_bpf_link)) {
        bpf_link__destroy(g_bpf_link);
        g_bpf_link = NULL;
    }
    if (g_bpf_obj && !libbpf_get_error(g_bpf_obj)) {
        bpf_object__close(g_bpf_obj);
        g_bpf_obj = NULL;
    }
    printf("\n [XDP-CLEANUP] 现代内核防御程序已安全释放。\n");
}

void l2c_net_block_ip(uint32_t ip_addr) {
    if (g_blacklist_map_fd < 0) return;
    uint8_t val = 1;
    bpf_map_update_elem(g_blacklist_map_fd, &ip_addr, &val, BPF_ANY);
}

void xdp_start_poll(const char *ifname, void (*lua_callback)(void* packet_ptr, int64_t len)) {
    struct rlimit r = {RLIM_INFINITY, RLIM_INFINITY};
    setrlimit(RLIMIT_MEMLOCK, &r);

    g_ifindex = if_nametoindex(ifname);
    if (!g_ifindex) {
        perror("无效的网卡名称");
        return;
    }

    printf(" [XDP-INIT] 正在加载内核字节码 bpf/kernel_killer.o ...\n");
    g_bpf_obj = bpf_object__open_file("bpf/kernel_killer.o", NULL);
    if (libbpf_get_error(g_bpf_obj)) {
        perror("加载 BPF 打开文件失败");
        g_bpf_obj = NULL;
        return;
    }

    if (bpf_object__load(g_bpf_obj)) {
        perror("BPF 加载到内核失败");
        bpf_object__close(g_bpf_obj);
        g_bpf_obj = NULL;
        return;
    }

    struct bpf_program *prog = bpf_object__find_program_by_name(g_bpf_obj, "xdp_killer_prog");
    if (!prog) {
        fprintf(stderr, "找不到 xdp_killer_prog 函数，请检查 kernel_killer.c 中的 SEC 定义！\n");
        bpf_object__close(g_bpf_obj);
        g_bpf_obj = NULL;
        return;
    }

    /* 
     * 【核心修复】：删除/注释掉下面的手动 attach! 
     * 避免与后续 xsk_socket__create 产生 EBUSY (-16) 冲突。
     
    g_bpf_link = bpf_program__attach_xdp(prog, g_ifindex);
    if (libbpf_get_error(g_bpf_link)) {
        fprintf(stderr, " [致命错误] 挂载 XDP 到网卡 %s 失败！请确认网卡状态或以 sudo 运行！\n", ifname);
        g_bpf_link = NULL; // 清空错误句柄，防止 cleanup_bpf 误销毁
        bpf_object__close(g_bpf_obj);
        g_bpf_obj = NULL;
        return;
    }
    atexit(cleanup_bpf);

    */

    g_blacklist_map_fd = bpf_object__find_map_fd_by_name(g_bpf_obj, "blacklist_map");
    g_xsks_map_fd = bpf_object__find_map_fd_by_name(g_bpf_obj, "xsks_map");
    if (g_blacklist_map_fd < 0 || g_xsks_map_fd < 0) {
        fprintf(stderr, "找不到 BPF Map (blacklist_map 或 xsks_map)\n");
        return;
    }

    // ========================================================
    // 2. 建立旁路通道 (AF_XDP UMEM)
    // ========================================================
    void *umem_area = NULL;
    if (posix_memalign(&umem_area, getpagesize(), NUM_FRAMES * FRAME_SIZE)) {
        perror("UMEM 内存分配失败");
        return; 
    }

    struct xsk_ring_prod fill_ring;
    struct xsk_ring_cons comp_ring, rx_ring;
    struct xsk_ring_prod tx_ring;
    struct xsk_umem *umem = NULL;
    struct xsk_umem_config umem_cfg = {
        .fill_size = 2048, 
        .comp_size = 2048, 
        .frame_size = FRAME_SIZE, 
        .frame_headroom = XSK_UMEM__DEFAULT_FRAME_HEADROOM
    };

    int ret = xsk_umem__create(&umem, umem_area, NUM_FRAMES * FRAME_SIZE, &fill_ring, &comp_ring, &umem_cfg);
    if (ret < 0) {
        fprintf(stderr, "xsk_umem__create 失败，错误码: %d\n", ret);
        return;
    }

    struct xsk_socket *xsk = NULL;
    // 【关键修复】：指定 XDP_FLAGS_SKB_MODE，确保适配 veth 虚拟网卡；使用 XDP_ZEROCOPY 或默认模式
    struct xsk_socket_config xsk_cfg = { 
        .rx_size = 2048, 
        .tx_size = 2048, 
        .xdp_flags = XDP_FLAGS_SKB_MODE, // veth 测试时开启 SKB 模式，避免挂载驱动冲突
        .bind_flags = XDP_USE_NEED_WAKEUP 
    };

    ret = xsk_socket__create(&xsk, ifname, 0, umem, &rx_ring, &tx_ring, &xsk_cfg);
    if (ret < 0 || !xsk) {
        fprintf(stderr, "xsk_socket__create 绑定网卡 %s 失败，错误码: %d\n", ifname, ret);
        return;
    }

    // 将 Socket 句柄更新至 BPF xsks_map
    int xsk_fd = xsk_socket__fd(xsk);
    if (xsk_fd < 0) {
        fprintf(stderr, "获取 xsk_fd 句柄无效！\n");
        return;
    }

    int key = 0; // rx_queue_index 默认为 0
    if (bpf_map_update_elem(g_xsks_map_fd, &key, &xsk_fd, BPF_ANY) < 0) {
        perror("更新 xsks_map 失败");
        return;
    }

    uint32_t idx_fill;
    uint32_t fill_qty = 2048; 
    if (xsk_ring_prod__reserve(&fill_ring, fill_qty, &idx_fill) == fill_qty) {
        for (uint32_t i = 0; i < fill_qty; i++) {
            *xsk_ring_prod__fill_addr(&fill_ring, idx_fill++) = i * FRAME_SIZE;
        }
        xsk_ring_prod__submit(&fill_ring, fill_qty);
    }

    printf(" [XDP-INIT] AF_XDP 极速嗅探引擎点火完毕 (监听网卡: %s)！\n", ifname);

    // ========================================================
    // 3. 进入极速轮询监听
    // ========================================================
    struct pollfd fds[1] = {{.fd = xsk_fd, .events = POLLIN}};

    while (1) {
        if (xsk_ring_prod__needs_wakeup(&fill_ring)) {
            poll(fds, 1, 10); 
        }

        uint32_t idx_rx;
        uint32_t rcvd = xsk_ring_cons__peek(&rx_ring, BATCH_SIZE, &idx_rx);
        if (!rcvd) {
            // 如果没有收到包，主动唤醒/等待内核
            if (xsk_ring_prod__needs_wakeup(&fill_ring)) {
                recvfrom(xsk_fd, NULL, 0, MSG_DONTWAIT, NULL, NULL); // 强制唤醒内核收包
            }
            usleep(100); // 避免 CPU 100% 空转，测试期可加微小休眠
            continue;
        }

        // 2. 收到包后的处理 ...
        // 【调试加这行】
        // printf("[AF_XDP C-Wrapper] 捕获到极速数据包，数量: %d\n", rcvd);
        
        uint32_t rx_start = idx_rx;
        for (uint32_t i = 0; i < rcvd; i++) {
            const struct xdp_desc *desc = xsk_ring_cons__rx_desc(&rx_ring, idx_rx++);
            void *pkt_ptr = (void *)((char *)umem_area + desc->addr);
            if (lua_callback) {
                lua_callback(pkt_ptr, (int64_t)(desc->len));
            }
        }
        xsk_ring_cons__release(&rx_ring, rcvd);

        // 3. 【核心】：收完包后，必须把这些内存帧重新还给 Fill Ring，供内核接收下一个包！
        uint32_t idx_fq;
        if (xsk_ring_prod__reserve(&fill_ring, rcvd, &idx_fq) == rcvd) {
            for (uint32_t i = 0; i < rcvd; i++) {
                *xsk_ring_prod__fill_addr(&fill_ring, idx_fq++) = xsk_ring_cons__rx_desc(&rx_ring, rx_start + i)->addr;
            }
            xsk_ring_prod__submit(&fill_ring, rcvd);
        }
    }
}
