// ==============================================================================
// Copyright (c) 2026 Panshaogui | MIT License
// L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
// ==============================================================================

// =========================================================================
// [L2C 蓝牙引擎]：NimBLE NUS 协议栈 (iPhone 无线控制台)
// =========================================================================

#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "host/ble_hs.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"

extern void l2c_wake_main_core(void);

// 专属的 0-GC 蓝牙接收缓冲
static uint8_t g_ble_rx_buf[256];
static volatile int g_ble_rx_head = 0;
static volatile int g_ble_rx_tail = 0;
static uint8_t g_ble_own_addr_type;

// 蓝牙收到手机发来数据的中断回调！
static int l2c_ble_rx_cb(uint16_t conn_handle, uint16_t attr_handle, struct ble_gatt_access_ctxt *ctxt, void *arg) {
    for(int i = 0; i < ctxt->om->om_len; i++) {
        uint8_t c = ctxt->om->om_data[i];
        int next_head = (g_ble_rx_head + 1) & 255;
        if(next_head != g_ble_rx_tail) {
            g_ble_rx_buf[g_ble_rx_head] = c;
            g_ble_rx_head = next_head;
        }
    }
    l2c_wake_main_core(); // 瞬间跨核踢醒 Core 0 处理命令！
    return 0;
}

// 经典的 Nordic UART Service UUID
static const ble_uuid128_t nus_svc_uuid = BLE_UUID128_INIT(0x9E,0xCA,0xDC,0x24,0x0E,0xE5,0xA9,0xE0,0x93,0xF3,0xA3,0xB5,0x01,0x00,0x40,0x6E);
static const ble_uuid128_t nus_rx_uuid  = BLE_UUID128_INIT(0x9E,0xCA,0xDC,0x24,0x0E,0xE5,0xA9,0xE0,0x93,0xF3,0xA3,0xB5,0x02,0x00,0x40,0x6E);

static const struct ble_gatt_svc_def g_l2c_gatt_svcs[] = {
    { .type = BLE_GATT_SVC_TYPE_PRIMARY, .uuid = &nus_svc_uuid.u,
        .characteristics = (struct ble_gatt_chr_def[]) {
        { .uuid = &nus_rx_uuid.u, .access_cb = l2c_ble_rx_cb, .flags = BLE_GATT_CHR_F_WRITE | BLE_GATT_CHR_F_WRITE_NO_RSP },
        { 0 }
        }
    }, { 0 }
};

static void l2c_ble_adv_start(void);
static int l2c_ble_gap_event(struct ble_gap_event *event, void *arg) {
    if (event->type == BLE_GAP_EVENT_DISCONNECT) { l2c_ble_adv_start(); } // 手机断开后自动重新广播
    return 0;
}

static void l2c_ble_adv_start(void) {
    struct ble_hs_adv_fields fields = {0};
    fields.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
    fields.name = (uint8_t *)"L2C-Mesh"; // 你的手机能搜到的名字！
    fields.name_len = 8;
    fields.name_is_complete = 1;
    ble_gap_adv_set_fields(&fields);

    struct ble_gap_adv_params adv_params = {0};
    adv_params.conn_mode = BLE_GAP_CONN_MODE_UND;
    adv_params.disc_mode = BLE_GAP_DISC_MODE_GEN;
    ble_gap_adv_start(g_ble_own_addr_type, NULL, BLE_HS_FOREVER, &adv_params, l2c_ble_gap_event, NULL);
}

static void l2c_ble_on_sync(void) {
    ble_hs_id_infer_auto(0, &g_ble_own_addr_type);
    l2c_ble_adv_start();
}

static void l2c_ble_host_task(void *param) {
    nimble_port_run();
    nimble_port_freertos_deinit();
}

static inline void l2c_ble_init(void) {
    nimble_port_init();
    ble_svc_gap_device_name_set("L2C-Mesh");
    ble_svc_gap_init();
    ble_svc_gatt_init();
    ble_gatts_count_cfg(g_l2c_gatt_svcs);
    ble_gatts_add_svcs(g_l2c_gatt_svcs);
    ble_hs_cfg.sync_cb = l2c_ble_on_sync;
    nimble_port_freertos_init(l2c_ble_host_task);
}

// 提供给 Teal 业务层的 0-GC 拉取函数
static inline int l2c_ble_pop_char(void) {
    if (g_ble_rx_head == g_ble_rx_tail) return -1;
    int c = g_ble_rx_buf[g_ble_rx_tail];
    g_ble_rx_tail = (g_ble_rx_tail + 1) & 255;
    return c;
}