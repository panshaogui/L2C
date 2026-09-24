// ==============================================================================
// Copyright (c) 2026 Panshaogui | MIT License
// L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
// ==============================================================================

#include "esp_ota_ops.h"
#include "esp_http_client.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include <string.h>

// 后台下载与烧写任务（不阻塞 UI 和雷达！）
static void l2c_ota_task(void *pvParameter) {
    char* url = (char*)pvParameter;
    printf("\n========== [L2C 空中兵工厂] ==========\n");
    printf(">> 目标固件: %s\n", url);

    esp_http_client_config_t config = {
        .url = url,
        .timeout_ms = 5000,
        .keep_alive_enable = true,
    };
    esp_http_client_handle_t client = esp_http_client_init(&config);
    
    if (esp_http_client_open(client, 0) != ESP_OK) {
        printf(" [OTA-ERR] 无法连接到指挥中心服务器!\n");
        goto clean;
    }
    
    esp_http_client_fetch_headers(client);
    int total_len = esp_http_client_get_content_length(client);
    printf(">> 固件大小侦测: %d Bytes\n", total_len);

    esp_ota_handle_t update_handle = 0;
    // 获取后台那个空闲的备用分区 (ota_0 或 ota_1)
    const esp_partition_t *update_part = esp_ota_get_next_update_partition(NULL);
    printf(">> 正在擦除备用物理分区: %s ...\n", update_part->label);
    
    if (esp_ota_begin(update_part, OTA_WITH_SEQUENTIAL_WRITES, &update_handle) != ESP_OK) {
        printf(" [OTA-ERR] 物理分区擦除失败!\n");
        goto clean;
    }

    char* ota_buf = malloc(4096);
    int written_len = 0;
    printf(">> 正在进行 HTTP 流式下载与 Flash 热烧写...\n");
    
    while (1) {
        int data_read = esp_http_client_read(client, ota_buf, 4096);
        if (data_read < 0) {
            printf(" [OTA-ERR] 下载意外中断!\n");
            break;
        } else if (data_read > 0) {
            esp_ota_write(update_handle, (const void *)ota_buf, data_read);
            written_len += data_read;
            if (written_len % (4096 * 20) == 0) {
                printf(">> 进度: %d / %d Bytes\n", written_len, total_len);
            }
        } else if (data_read == 0) {
            break; // 下载完毕
        }
    }
    free(ota_buf);
    
    if (written_len == total_len) {
        esp_ota_end(update_handle);
        if (esp_ota_set_boot_partition(update_part) == ESP_OK) {
            printf(" [OTA 成功] 固件写入完毕！引导区已切换！3秒后系统热重启！\n");
            vTaskDelay(pdMS_TO_TICKS(3000));
            esp_restart();
        }
    } else {
        printf(" [OTA-ERR] 固件下载不完整，已回滚！\n");
    }

clean:
    esp_http_client_cleanup(client);
    free(url);
    vTaskDelete(NULL);
}

// 供 Teal 调用的探针
int l2c_ota_start(const char* url) {
    char* url_copy = strdup(url); 
    // 开辟独立的 FreeRTOS 线程去拉取，绝对不卡死 UI 和射频中断！
    xTaskCreate(&l2c_ota_task, "ota_task", 8192, url_copy, 5, NULL);
    return 1;
}