// ==============================================================================
// Copyright (c) 2026 Panshaogui | MIT License
// L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
// ==============================================================================

#include <stdint.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

// =========================================================================
// [1] SPSC 战术字符串消息队列 (Core 1 写入，Core 0 读取)
// =========================================================================
#define C2_MSG_Q_SIZE 16
#define C2_MSG_MAX_LEN 128
static uint8_t g_c2_msg_q[C2_MSG_Q_SIZE][C2_MSG_MAX_LEN];
static volatile int g_c2_msg_head = 0;
static volatile int g_c2_msg_tail = 0;

int l2c_c2_msg_push(void* str_ptr) {
    int next_head = (g_c2_msg_head + 1) % C2_MSG_Q_SIZE;
    if (next_head == g_c2_msg_tail) return 0; // 满载保护

    uint8_t* src = (uint8_t*)str_ptr;
    int len = src[0];
    if (len > C2_MSG_MAX_LEN - 2) len = C2_MSG_MAX_LEN - 2;

    g_c2_msg_q[g_c2_msg_head][0] = len;
    memcpy(&g_c2_msg_q[g_c2_msg_head][1], &src[1], len);
    g_c2_msg_q[g_c2_msg_head][len + 1] = '\0';

    __sync_synchronize(); 
    g_c2_msg_head = next_head;
    return 1;
}

int l2c_c2_msg_pop(void* str_ptr) {
    if (g_c2_msg_head == g_c2_msg_tail) return 0;

    uint8_t* dst = (uint8_t*)str_ptr;
    int len = g_c2_msg_q[g_c2_msg_tail][0];
    
    dst[0] = len;
    memcpy(&dst[1], &g_c2_msg_q[g_c2_msg_tail][1], len);
    dst[len + 1] = '\0';

    __sync_synchronize();
    g_c2_msg_tail = (g_c2_msg_tail + 1) % C2_MSG_Q_SIZE;
    return 1;
}

// =========================================================================
// [2] 战术兵力登记册 (硬件互斥锁防多核撕裂)
// =========================================================================
#define MAX_FLEET 8
typedef struct {
    uint32_t ip;
    uint32_t last_seen_ticks;
} fleet_node_t;

static fleet_node_t g_fleet[MAX_FLEET] = {0};
static portMUX_TYPE g_fleet_mux = portMUX_INITIALIZER_UNLOCKED;

int l2c_c2_fleet_update(uint32_t ip) {
    if (ip == 0) return 0;
    int is_new = 1;
    uint32_t now = xTaskGetTickCount();

    taskENTER_CRITICAL(&g_fleet_mux);
    int empty_idx = -1;
    for (int i = 0; i < MAX_FLEET; i++) {
        if (g_fleet[i].ip == ip) {
            g_fleet[i].last_seen_ticks = now;
            is_new = 0;
            break;
        }
        if (g_fleet[i].ip == 0 && empty_idx == -1) {
            empty_idx = i;
        }
    }
    if (is_new && empty_idx >= 0) {
        g_fleet[empty_idx].ip = ip;
        g_fleet[empty_idx].last_seen_ticks = now;
    }
    taskEXIT_CRITICAL(&g_fleet_mux);
    return is_new;
}

int l2c_c2_fleet_get_active(void* out_ips_ptr) {
    uint32_t* ips = (uint32_t*)out_ips_ptr;
    uint32_t now = xTaskGetTickCount();
    uint32_t timeout_ticks = pdMS_TO_TICKS(35000); // 35秒掉线法则
    int count = 0;

    taskENTER_CRITICAL(&g_fleet_mux);
    for (int i = 0; i < MAX_FLEET; i++) {
        if (g_fleet[i].ip != 0) {
            if ((now - g_fleet[i].last_seen_ticks) > timeout_ticks) {
                g_fleet[i].ip = 0; // 超时物理剔除
            } else {
                ips[count++] = g_fleet[i].ip;
            }
        }
    }
    taskEXIT_CRITICAL(&g_fleet_mux);
    return count;
}