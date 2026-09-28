// ==============================================================================
// Copyright (c) 2026 Panshaogui | MIT License
// L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
// ==============================================================================

// =========================================================================
// [L2C 磁盘引擎]：TF 卡 SPI 极速挂载与 0-GC 日志写入 (ESP-IDF v5 适配版)
// =========================================================================

#include "esp_vfs_fat.h"
#include "sdmmc_cmd.h"
#include "driver/sdspi_host.h"
#include "driver/spi_master.h"
#include "esp_err.h"
#include "driver/gpio.h" 

// [全局唯一] 战术黑匣子物理句柄
static sdmmc_card_t* g_l2c_sd_card = NULL;

// =========================================================================
// [大一统 0-GC 挂载引擎] 动态支持任意 SPI_HOST 与 隔离引脚！
// =========================================================================
int l2c_sdcard_init_unified(int host_id, int miso, int mosi, int sck, int cs, int isolate_pin) {
    if (g_l2c_sd_card) return 1; // 防炸鸡：如果已经挂载成功，直接返回！

    // 0. [动态防线] 如果板子需要物理隔离（比如微雪的屏幕片选 45），强行拉高！
    if (isolate_pin >= 0) {
        gpio_set_direction(isolate_pin, GPIO_MODE_OUTPUT);
        gpio_set_level(isolate_pin, 1);
    }

    // 2. 挂载 SD 卡
    esp_vfs_fat_sdmmc_mount_config_t mount_config = {
        .format_if_mount_failed = false,
        .max_files = 5,
        .allocation_unit_size = 16 * 1024
    };
    
    sdmmc_host_t host = SDSPI_HOST_DEFAULT();
    host.slot = host_id; // 动态挂载到 SPI2 或 SPI3
    host.max_freq_khz = SDMMC_FREQ_DEFAULT; 
    
    sdspi_device_config_t slot_config = SDSPI_DEVICE_CONFIG_DEFAULT();
    slot_config.gpio_cs = cs;
    slot_config.host_id = host.slot;
    
    esp_err_t mnt_ret = esp_vfs_fat_sdspi_mount("/sd", &host, &slot_config, &mount_config, &g_l2c_sd_card);
    
    return (mnt_ret == ESP_OK) ? 1 : 0;
}

// =========================================================================
// [对外接口] 优雅兼容两套开发板的 Teal 探针
// =========================================================================

// 兼容亿佰特 EoRa-S3：使用 SPI3，无隔离引脚 (-1)
int l2c_sdcard_init(int miso, int mosi, int sck, int cs) {
    return l2c_sdcard_init_unified(SPI3_HOST, miso, mosi, sck, cs, -1);
}

// 兼容微雪 Touch-LCD-2：使用 SPI2，隔离 LCD 引脚 45
int l2c_sdcard_init1(int miso, int mosi, int sck, int cs) {
    return l2c_sdcard_init_unified(SPI2_HOST, miso, mosi, sck, cs, 45);
}

// 0-GC 极速日志追加：用完即毁，绝不占用堆内存！
static inline void l2c_sdcard_append(const char* filename, const char* text) {
    if (!g_l2c_sd_card) return; // 防炸鸡：没插卡就直接丢弃
    char path[64];
    snprintf(path, sizeof(path), "/sd/%s", filename);
    FILE* f = fopen(path, "a");
    if (!f) return;
    fprintf(f, "%s\n", text);
    fclose(f);
}