// ==============================================================================
// Copyright (c) 2026 Panshaogui | MIT License
// L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
// ==============================================================================

// clib/mcu/esp32_udp.c
// =========================================================================
// [L2C 核心库]：ESP32 极速 UDP 战术数据回传引擎
// =========================================================================

#include "lwip/sockets.h"
#include "lwip/netdb.h"
#include <fcntl.h> // [新增] 用于设置 O_NONBLOCK 非阻塞标志

// =========================================================================
// [接收端] 0-GC UDP 异步命令引擎 (用于接收 Mac 下发的指令)
// =========================================================================
static int g_l2c_udp_sock = -1;

void l2c_udp_server_init(int port) {
    if (g_l2c_udp_sock >= 0) return; // 防止重复初始化
    g_l2c_udp_sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_IP);
    if (g_l2c_udp_sock < 0) return;

    struct sockaddr_in dest_addr;
    dest_addr.sin_addr.s_addr = htonl(INADDR_ANY);
    dest_addr.sin_family = AF_INET;
    dest_addr.sin_port = htons(port);

    bind(g_l2c_udp_sock, (struct sockaddr *)&dest_addr, sizeof(dest_addr));

    // [核心装甲] 强制设置为 O_NONBLOCK，防止 recvfrom 卡死主核调度！
    int flags = fcntl(g_l2c_udp_sock, F_GETFL, 0);
    fcntl(g_l2c_udp_sock, F_SETFL, flags | O_NONBLOCK);
}

// 0-GC 极速弹出 UDP 指令，直接映射进 StackString
int l2c_udp_pop_cmd(void* str_ptr, int max_len) {
    if (g_l2c_udp_sock < 0) return 0;
    
    uint8_t* p = (uint8_t*)str_ptr;
    struct sockaddr_storage source_addr;
    socklen_t socklen = sizeof(source_addr);
    
    int len = recvfrom(g_l2c_udp_sock, p + 1, max_len - 1, 0, (struct sockaddr *)&source_addr, &socklen);
    
    if (len > 0) {
        p[0] = (uint8_t)len;       // 设置 L2C 长度头
        p[len + 1] = '\0';         // C 语言安全封口
        return 1;
    }
    return 0;
}

// =========================================================================
// [发送端] 0-GC 极速探针：复用监听端口的 Socket，免去建立连接的极高开销！
// =========================================================================
void l2c_udp_send(const char* target_ip, int target_port, const void* data, int len) {
    if (len <= 0 || !data) return;

    // [核心优化] 如果接收端的炮管已经建好，直接复用！
    int sock = g_l2c_udp_sock;
    int is_temp = 0;
    if (sock < 0) {
        sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_IP);
        if (sock < 0) return;
        is_temp = 1;
    }

    struct sockaddr_in dest_addr;
    dest_addr.sin_addr.s_addr = inet_addr(target_ip);
    dest_addr.sin_family = AF_INET;
    dest_addr.sin_port = htons(target_port);

    sendto(sock, data, len, 0, (struct sockaddr *)&dest_addr, sizeof(dest_addr));
    
    // 只有临时建的炮管才销毁，主炮管常驻！
    if (is_temp) close(sock);
}