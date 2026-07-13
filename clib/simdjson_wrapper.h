// ==============================================================================
// Copyright (c) 2026 Panshaogui | MIT License
// L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
// ==============================================================================

#ifndef SIMDJSON_WRAPPER_H
#define SIMDJSON_WRAPPER_H

/* 
 * 物理封印：如果在 C++ 环境下编译，启用 extern "C"；
 * 如果被 L2C 的纯 C 编译器引入，则作为普通 C 函数声明！
 */
#ifdef __cplusplus
extern "C" {
#endif

void* simdjson_c_parse(const char* json_str, int len);
double simdjson_c_get_number(void* ptr, const char* key);
void simdjson_c_free(void* ptr);

#ifdef __cplusplus
}
#endif

#endif
