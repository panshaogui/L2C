// ==============================================================================
// Copyright (c) 2026 Panshaogui | MIT License
// L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
// ==============================================================================

// clib/mcu/esp32_ntp.c
// =========================================================================
// [L2C 核心库]：ESP32 极速 NTP 军工级时间同步引擎
// =========================================================================
#include "esp_sntp.h"
#include <time.h>
#include <sys/time.h>

extern void l2c_str_init(void* ptr);
extern void l2c_str_append_cstr(void* ptr, int max_len, const char* str);

static inline void l2c_ntp_init(void) {
    esp_sntp_setoperatingmode(SNTP_OPMODE_POLL);
    esp_sntp_setservername(0, "pool.ntp.org");
    esp_sntp_setservername(1, "time.apple.com");
    esp_sntp_setservername(2, "time.google.com");
    esp_sntp_init();
    
    // 【专属时区定位】：Asia/Shanghai (CST, UTC+8)
    setenv("TZ", "CST-8", 1);
    tzset();
}

static inline int l2c_ntp_is_synced(void) {
    return sntp_get_sync_status() == SNTP_SYNC_STATUS_COMPLETED ? 1 : 0;
}

// 0-GC 极速提取格式化时间 (例如 "2026-09-10 14:20:00")
static inline void l2c_ntp_get_time_str(void* str_ptr) {
    time_t now;
    struct tm timeinfo;
    time(&now);
    localtime_r(&now, &timeinfo);
    
    l2c_str_init(str_ptr);
    
    // 如果年份小于 2020，说明 NTP 还没同步完成
    if (timeinfo.tm_year < (2020 - 1900)) {
        l2c_str_append_cstr(str_ptr, 64, "UNSYNCED");
    } else {
        char strftime_buf[64];
        strftime(strftime_buf, sizeof(strftime_buf), "%Y-%m-%d %H:%M:%S", &timeinfo);
        l2c_str_append_cstr(str_ptr, 64, strftime_buf);
    }
}