// ==============================================================================
// Copyright (c) 2026 Panshaogui | MIT License
// L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
// ==============================================================================

#pragma once
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>

void l2c_str_init(void* ptr);
void l2c_str_clear(void* ptr);
void l2c_str_append_char(void* ptr, int max_len, char c);
void l2c_str_append_cstr(void* ptr, int max_len, const char* str);
void l2c_str_append_int(void* ptr, int max_len, int val);
const char* l2c_str_get(void* ptr);
int l2c_str_len(void* ptr);
int l2c_str_eq(void* ptr, const char* cmp);
int l2c_str_to_int(void* ptr);