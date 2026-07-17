// ==============================================================================
// Copyright (c) 2026 Panshaogui | MIT License
// L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
// ==============================================================================

#ifndef XDP_WRAPPER_H
#define XDP_WRAPPER_H

/* 
 * 物理封印：向 L2C 和 Nelua 提供底层的函数签名声明
 */
#ifdef __cplusplus
extern "C" {
#endif

// 暴露给 L2C 的核心入口
void xdp_start_poll(const char *ifname, void (*lua_callback)(void* packet_ptr, int len));

#ifdef __cplusplus
}
#endif

#endif
