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

static sdmmc_card_t* g_l2c_sd_card = NULL;

static inline int l2c_sdcard_init(int miso, int mosi, int sck, int cs) {
    esp_vfs_fat_sdmmc_mount_config_t mount_config = {
        .format_if_mount_failed = false,
        .max_files = 5,
        .allocation_unit_size = 16 * 1024
    };
    
    spi_bus_config_t bus_cfg = {
        .mosi_io_num = mosi, .miso_io_num = miso, .sclk_io_num = sck,
        .quadwp_io_num = -1, .quadhd_io_num = -1, .max_transfer_sz = 4000
    };
    if (spi_bus_initialize(SPI3_HOST, &bus_cfg, SPI_DMA_CH_AUTO) != ESP_OK) return -1;

    // 【核心修复：补全 ESP-IDF v5 强制要求的 Host 配置器！】
    sdmmc_host_t host = SDSPI_HOST_DEFAULT();
    host.slot = SPI3_HOST;

    sdspi_device_config_t slot_config = SDSPI_DEVICE_CONFIG_DEFAULT();
    slot_config.gpio_cs = cs;
    slot_config.host_id = host.slot;

    // 【核心修复：传入 5 个参数 (加入了 &host)，完美对齐 C 语言底层指针！】
    if (esp_vfs_fat_sdspi_mount("/sd", &host, &slot_config, &mount_config, &g_l2c_sd_card) != ESP_OK) {
        return -2;
    }
    return 0;
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