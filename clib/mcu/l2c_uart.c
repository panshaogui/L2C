// ==============================================================================
// Copyright (c) 2026 Panshaogui | MIT License
// L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
// ==============================================================================

// clib/mcu/l2c_uart.c
// [L2C 串口 CMD 探针]：VFS 安全直通，防止抢夺底层 UART 导致崩溃

#include <stdio.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static inline void l2c_uart_init(void) {
    // 白嫖 ESP-IDF 已经配置好的 VFS UART，什么都不用做！
}

// 安全阻塞读取，防看门狗熔断
static inline int l2c_uart_read_char(void) {
    int c = fgetc(stdin);
    if (c == EOF) {
        // 如果 VFS 处于非阻塞模式没读到数据，强行让出 10ms 的 CPU 切片！
        // 这极其关键！它防止了 Core 1 陷入 100% 空转而触发看门狗重启！
        vTaskDelay(1); 
        return -1;
    }
    return c;
}