// ==============================================================================
// Copyright (c) 2026 Panshaogui | MIT License
// L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
// ==============================================================================

// 使用 1 字节记录长度 (最大 255 字符)，完美避开芯片的内存对齐异常！
// 内存布局: ptr[0] = length, ptr[1...N] = chars, ptr[N+1] = '\0'

#include "clib/stackstring.h"
#include <string.h>
#include <stdio.h>

void l2c_str_init(void* ptr) {
    uint8_t* p = (uint8_t*)ptr;
    p[0] = 0;      // 长度归零
    p[1] = '\0';   // C 语言字符串结尾
}

void l2c_str_clear(void* ptr) {
    l2c_str_init(ptr);
}

// 压入单个字符 (极其适合串口单字节接收)
void l2c_str_append_char(void* ptr, int max_len, char c) {
    uint8_t* p = (uint8_t*)ptr;
    if (p[0] < max_len - 1) {
        p[0]++;              // 长度 +1
        p[p[0]] = c;         // 写入字符
        p[p[0] + 1] = '\0';  // 重新封口
    }
}

// 压入静态 C 字符串
void l2c_str_append_cstr(void* ptr, int max_len, const char* str) {
    uint8_t* p = (uint8_t*)ptr;
    while (*str && p[0] < max_len - 1) {
        p[0]++;
        p[p[0]] = *str++;
    }
    p[p[0] + 1] = '\0';
}

// 0-GC 极速整数转字符串追加，写日志必备
void l2c_str_append_int(void* ptr, int max_len, int val) {
    char num[16];
    snprintf(num, sizeof(num), "%d", val);
    l2c_str_append_cstr(ptr, max_len, num);
}

// 提取标准的 C 字符串指针 (可以直接传给 print, nvs_set_str, Oled 等)
const char* l2c_str_get(void* ptr) {
    return (const char*)((uint8_t*)ptr + 1);
}

int l2c_str_len(void* ptr) {
    return ((uint8_t*)ptr)[0];
}

// 0-GC 极速字符串比较
int l2c_str_eq(void* ptr, const char* cmp) {
    return strcmp((const char*)((uint8_t*)ptr + 1), cmp) == 0;
}

// 0-GC 极速整数解析 (用于解析 freq 433 命令)
int l2c_str_to_int(void* ptr) {
    return atoi((const char*)((uint8_t*)ptr + 1));
}