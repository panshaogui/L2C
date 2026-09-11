// ==============================================================================
// Copyright (c) 2026 Panshaogui | MIT License
// L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
// ==============================================================================

// =========================================================================
// L2C 0-GC 非易失性存储引擎 (NVS)
// =========================================================================

#include "nvs_flash.h"
#include "nvs.h"

// 全局静态 NVS 句柄
static nvs_handle_t g_l2c_nvs_handle;

static inline void l2c_nvs_init(void) {
    // 初始化默认的 NVS 分区
    esp_err_t err = nvs_flash_init();
    // 物理防漏水：如果遇到版本不匹配或没有空闲页，直接物理擦除后重建！
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        nvs_flash_erase();
        err = nvs_flash_init();
    }
    // 打开名为 "storage" 的命名空间，权限为读写
    nvs_open("storage", NVS_READWRITE, &g_l2c_nvs_handle);
}

// 0-GC 极速读取 (带默认值兜底)
static inline int32_t l2c_nvs_get_int(const char* key, int32_t default_val) {
    int32_t val = 0;
    esp_err_t err = nvs_get_i32(g_l2c_nvs_handle, key, &val);
    if (err != ESP_OK) return default_val;
    return val;
}

// 0-GC 极速写入 (写入后自动提交到物理 Flash)
static inline void l2c_nvs_set_int(const char* key, int32_t val) {
    nvs_set_i32(g_l2c_nvs_handle, key, val);
    nvs_commit(g_l2c_nvs_handle);
}

// =========================================================================
// [L2C 黑匣子] 0-GC NVS 字符串加密存取引擎
// =========================================================================

int l2c_nvs_set_stackstr(const char* key, void* str_ptr) {
    nvs_handle_t handle;
    if (nvs_open("storage", NVS_READWRITE, &handle) == ESP_OK) {
        // 直接读取 StackString 偏移 1 处的原生 C 字符串
        nvs_set_str(handle, key, (const char*)((uint8_t*)str_ptr + 1));
        nvs_commit(handle);
        nvs_close(handle);
        return 1;
    }
    return 0;
}

int l2c_nvs_get_stackstr(const char* key, void* str_ptr, int max_len) {
    nvs_handle_t handle;
    if (nvs_open("storage", NVS_READONLY, &handle) == ESP_OK) {
        size_t req_len = 0;
        // 先探测长度，如果存在且未越界，直接提取！
        if (nvs_get_str(handle, key, NULL, &req_len) == ESP_OK && req_len <= max_len) {
            nvs_get_str(handle, key, (char*)((uint8_t*)str_ptr + 1), &req_len);
            ((uint8_t*)str_ptr)[0] = (uint8_t)(req_len - 1); // 自动补齐 0-GC 长度头
            nvs_close(handle);
            return 1;
        }
        nvs_close(handle);
    }
    return 0;
}