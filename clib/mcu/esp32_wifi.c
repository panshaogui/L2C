// ==============================================================================
// Copyright (c) 2026 Panshaogui | MIT License
// L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
// ==============================================================================

// clib/mcu/esp32_wifi.c
// =========================================================================
// [L2C 核心库]：ESP32 极速自治 WiFi 状态机
// =========================================================================

#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_system.h"
#include "esp_wifi.h"
#include "esp_event.h"
#include "lwip/err.h"
#include "lwip/sys.h"
#include "esp_netif.h"

// 引入咱们之前写好的 StackString 函数通行证
extern void l2c_str_init(void* ptr);
extern void l2c_str_append_cstr(void* ptr, int max_len, const char* str);

static int g_l2c_wifi_connected = 0;
static char g_l2c_wifi_ip[32] = {0};

// 后台异步事件回调处理器
static void wifi_event_handler(void* arg, esp_event_base_t event_base, int32_t event_id, void* event_data) {
    if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_START) {
        esp_wifi_connect();
    } else if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_DISCONNECTED) {
        g_l2c_wifi_connected = 0;
        esp_wifi_connect(); // 【无限自动重连，死磕到底！】
    } else if (event_base == IP_EVENT && event_id == IP_EVENT_STA_GOT_IP) {
        ip_event_got_ip_t* event = (ip_event_got_ip_t*) event_data;
        snprintf(g_l2c_wifi_ip, sizeof(g_l2c_wifi_ip), IPSTR, IP2STR(&event->ip_info.ip));
        g_l2c_wifi_connected = 1;
    }
}

// 0-GC 极速初始化探针
void l2c_wifi_init_sta(const char* ssid, const char* pass) {
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_create_default_wifi_sta();

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));

    // 挂载监听器
    ESP_ERROR_CHECK(esp_event_handler_instance_register(WIFI_EVENT, ESP_EVENT_ANY_ID, &wifi_event_handler, NULL, NULL));
    ESP_ERROR_CHECK(esp_event_handler_instance_register(IP_EVENT, IP_EVENT_STA_GOT_IP, &wifi_event_handler, NULL, NULL));

    wifi_config_t wifi_config = {0};
    strncpy((char*)wifi_config.sta.ssid, ssid, sizeof(wifi_config.sta.ssid) - 1);
    strncpy((char*)wifi_config.sta.password, pass, sizeof(wifi_config.sta.password) - 1);

    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &wifi_config));
    ESP_ERROR_CHECK(esp_wifi_start());
}

int l2c_wifi_is_connected(void) {
    return g_l2c_wifi_connected;
}

// 0-GC 物理内存提取，直接把 IP 写入传进来的栈字符串！
void l2c_wifi_get_ip_str(void* str_ptr) {
    l2c_str_init(str_ptr);
    if (g_l2c_wifi_connected) {
        l2c_str_append_cstr(str_ptr, 64, g_l2c_wifi_ip);
    } else {
        l2c_str_append_cstr(str_ptr, 64, "0.0.0.0");
    }
}

// [网络装甲] 强制关闭 Wi-Fi 休眠，换取 1ms 级超低延迟！
void l2c_wifi_disable_power_save(void) {
    esp_wifi_set_ps(WIFI_PS_NONE);
}