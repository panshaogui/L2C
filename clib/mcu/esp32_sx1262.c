// ==============================================================================
// Copyright (c) 2026 Panshaogui | MIT License
// L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
// ==============================================================================

// =========================================================================
// [L2C 射频引擎]：ESP-IDF 极速 SPI 底层驱动 (SX1262 专用)
// =========================================================================

#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "driver/gpio.h"
#include "esp_attr.h"
#include "driver/spi_master.h"

static int g_sx1262_busy_pin = -1;
static spi_device_handle_t g_sx1262_spi_handle= NULL;

static inline void l2c_sx1262_set_busy_pin(int busy_pin) {
    g_sx1262_busy_pin = busy_pin;
    gpio_set_direction(busy_pin, GPIO_MODE_INPUT);
}

// 物理级强制死盯 BUSY：当 BUSY 为高电平时，禁止任何 SPI 读写！
static inline bool l2c_sx1262_wait_busy(void) {
    if (g_sx1262_busy_pin < 0) return true;
    uint32_t timeout = 50000; // ~50ms 超时
    while (gpio_get_level(g_sx1262_busy_pin) == 1) {
        timeout--;
        if (timeout == 0) {
            // 物理锁死异常！
            return false;
        }
        esp_rom_delay_us(1);
    }
    return true;
}

static inline void l2c_sx1262_spi_init(int sck, int miso, int mosi) {
    spi_bus_config_t buscfg = {
        .miso_io_num = miso,
        .mosi_io_num = mosi,
        .sclk_io_num = sck,
        .quadwp_io_num = -1,
        .quadhd_io_num = -1,
        .max_transfer_sz = 256
    };
    // 【核心修复：传入 0，强行关闭 DMA！短包通信绝对不走 DMA！】
    spi_bus_initialize(SPI2_HOST, &buscfg, 0);
    
    spi_device_interface_config_t devcfg = {
        .clock_speed_hz = 10 * 1000 * 1000, // 10MHz 极限通讯频率 (SX1262 支持最高 16MHz)
        .mode = 0,                          // SPI CPOL=0, CPHA=0 (时钟极性与相位)
        .spics_io_num = -1,                 // CS 引脚设为 -1，由咱们的 L2C 引擎手动精准控制！
        .queue_size = 1,
        .flags = 0,
    };
    // 将 SX1262 挂载到总线
    spi_bus_add_device(SPI2_HOST, &devcfg, &g_sx1262_spi_handle);
}

// 利用硬件 FIFO 直接收发 2 字节！】
static inline int l2c_sx1262_spi_xfer_2b(int b0, int b1) {
    spi_transaction_t t = {0};
    t.length = 16; // 传输 16 bit (2 字节)
    // 开启硬件 FIFO 直通魔法标志，彻底无视指针和 DMA！
    t.flags = SPI_TRANS_USE_TXDATA | SPI_TRANS_USE_RXDATA;
    t.tx_data[0] = (uint8_t)b0;
    t.tx_data[1] = (uint8_t)b1;
    
    spi_device_polling_transmit(g_sx1262_spi_handle, &t);
    
    // 拼装接收到的 2 个字节返回 (高 8 位是 byte0，低 8 位是 byte1)
    return (t.rx_data[0] << 8) | t.rx_data[1];
}

// [新增引擎] 绕过无 DMA 模式 64 字节物理瓶颈的连发切片轰炸机
static inline esp_err_t l2c_spi_transmit_chunked(uint8_t* tx, uint8_t* rx, int len) {
    esp_err_t ret = ESP_OK;
    int offset = 0;
    while (len > 0) {
        int chunk = (len > 64) ? 64 : len; // 强行切片，迎合 FIFO 极值
        spi_transaction_t t = {0};
        t.length = chunk * 8;
        t.tx_buffer = tx ? tx + offset : NULL;
        t.rx_buffer = rx ? rx + offset : NULL;
        ret = spi_device_polling_transmit(g_sx1262_spi_handle, &t);
        if (ret != ESP_OK) break;
        offset += chunk;
        len -= chunk;
    }
    return ret;
}

static inline void l2c_sx1262_spi_write_buffer(void* tx_data, int len) {
    l2c_spi_transmit_chunked((uint8_t*)tx_data, NULL, len);
}

// 0-GC 极速 Payload 提取探针 (防栈溢出+支持 Meshtastic 长包)
static inline void l2c_sx1262_write_payload_from_str(void* str_ptr, int offset) {
    uint8_t str_len = ((uint8_t*)str_ptr)[0];
    if (offset >= str_len) return;
    int pay_len = str_len - offset;
    uint8_t* payload = (uint8_t*)str_ptr + 1 + offset;

    // 扩容为 260 字节，防止 255 长包溢出栈内存
    uint8_t buf[260];
    buf[0] = 0x0E; // [核心修复] 0x0E 才是真正的 WriteBuffer 指令！
    buf[1] = 0x00; // 永远从 FIFO 基址 0 开始写
    memcpy(&buf[2], payload, pay_len);
    
    l2c_spi_transmit_chunked(buf, NULL, pay_len + 2);
}

static inline void l2c_sx1262_read_payload_to_str(int offset, int pay_len, void* str_ptr) {
    if (pay_len <= 0 || pay_len > 255) return;
    
    uint8_t tx_buf[260] = {0};
    uint8_t rx_buf[260] = {0};
    tx_buf[0] = 0x1E;    // ReadBuffer 指令
    tx_buf[1] = offset;  // 物理底核地址
    tx_buf[2] = 0x00;    // [核心修复] 强制注入 NOP (Dummy Byte) 空跑时钟
    
    // [核心修复] 1字节指令 + 1字节地址 + 1字节NOP + 报文长度 = pay_len + 3
    l2c_spi_transmit_chunked(tx_buf, rx_buf, pay_len + 3);
    
    uint8_t* p = (uint8_t*)str_ptr;
    p[0] = pay_len;
    // [核心修复] SX1262 的真实数据从偏移 3 开始！
    memcpy(&p[1], &rx_buf[3], pay_len);
    p[pay_len + 1] = '\0';
}

static inline int l2c_sx1262_spi_transfer_safe(void* tx_data, void* rx_data, int len) {
    if (!l2c_sx1262_wait_busy()) {
        return -1;
    }

    uint8_t dummy_rx[260];
    void* actual_rx = (rx_data != NULL) ? rx_data : dummy_rx;

    if (l2c_spi_transmit_chunked((uint8_t*)tx_data, (uint8_t*)actual_rx, len) != ESP_OK) {
        return -1;
    }

    uint8_t status_byte = ((uint8_t*)actual_rx)[0];
    uint8_t cmd_status = (status_byte >> 1) & 0x07;

    if (cmd_status == 0x03 || cmd_status == 0x04) {
        return -2;
    }

    return (int)status_byte;
}

// [核心修复：8-Bit 物理探针，专用于射频报文读写]
static inline void l2c_set_byte(void* ptr, int idx, int val) { ((uint8_t*)ptr)[idx] = (uint8_t)val; }
static inline int l2c_get_byte(void* ptr, int idx) { return (int)(((uint8_t*)ptr)[idx]); }

// [新增：SX1262 极速频率计算器 (防止 32 位溢出，利用 64 位硬算)]
// 公式: (freq_kHz * 1000 * 2^25) / 32,000,000
static inline int l2c_sx1262_calc_freq(int khz) {
    uint64_t f = (uint64_t)khz * 1000ULL;
    return (int)((f * 33554432ULL) / 32000000ULL);
}

// =========================================================================
// [L2C 中断引擎]：0-GC 微秒级射频唤醒 (Hardware ISR + Task Notify)
// =========================================================================

static volatile TaskHandle_t g_l2c_main_task_handle = NULL; // 增加 volatile 防止 ISR 寄存器重排

// 硬件中断回调函数 (必须放在 IRAM 内存中，防止 Flash 缓存未命中崩溃)
static void IRAM_ATTR l2c_dio1_isr_handler(void* arg) {
    if (g_l2c_main_task_handle != NULL) {
        BaseType_t xHigherPriorityTaskWoken = pdFALSE;
        // 发送轻量级任务通知，瞬间踢醒主线程！
        vTaskNotifyGiveFromISR(g_l2c_main_task_handle, &xHigherPriorityTaskWoken);
        if (xHigherPriorityTaskWoken) {
            portYIELD_FROM_ISR(); // 触发上下文切换，退出中断立刻执行主线程
        }
    }
}

// 初始化 DIO1 引脚为上升沿中断
static inline void l2c_setup_dio1_interrupt(int dio1_pin) {
    // 记住当前挂起的任务句柄 (也就是咱们的 main 主线程)
    g_l2c_main_task_handle = xTaskGetCurrentTaskHandle();

    gpio_config_t io_conf = {
        .intr_type = GPIO_INTR_POSEDGE, // 上升沿触发
        .pin_bit_mask = (1ULL << dio1_pin),
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = 0,
        .pull_down_en = 0
    };
    gpio_config(&io_conf);

    // 安装全局 GPIO 中断服务 (如果已被其他库安装，这里会报错但无妨，咱们忽略即可)
    gpio_install_isr_service(ESP_INTR_FLAG_IRAM);
    // 挂载 DIO1 的专署回调
    gpio_isr_handler_add(dio1_pin, l2c_dio1_isr_handler, NULL);
}

// 让主线程进入深渊沉睡，直到被射频中断踢醒 (0 CPU 占用！)
static inline void l2c_wait_for_radio(void) {
    // pdTRUE 表示唤醒后清空信号量，portMAX_DELAY 表示死等，绝不提前醒来
    ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
}

// [新增] 带有超时的深渊沉睡 (用于自动扫频雷达)
// 返回 1 表示被中断踢醒，0 表示超时自然醒
static inline int l2c_wait_for_radio_ms(int ms) {
    return ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(ms)) > 0 ? 1 : 0;
}

// 允许副核 Core 1 强行踢醒主核 Core 0
void l2c_wake_main_core(void) {
    if (g_l2c_main_task_handle != NULL) {
        xTaskNotifyGive(g_l2c_main_task_handle);
    }
}

// =========================================================================
// [L2C Meshtastic 战术解码探针] 0-GC 直接穿透 StackString 内存
// =========================================================================

// 提取 Destination (目标地址 4 字节)
int l2c_mesh_get_to(void* str_ptr) {
    if (((uint8_t*)str_ptr)[0] < 16) return 0;
    return *(int*)((uint8_t*)str_ptr + 1 + 0); 
}

// 提取 Source (来源地址 4 字节)
int l2c_mesh_get_from(void* str_ptr) {
    if (((uint8_t*)str_ptr)[0] < 16) return 0;
    return *(int*)((uint8_t*)str_ptr + 1 + 4); 
}

// 提取 Packet ID (报文编号 4 字节)
int l2c_mesh_get_id(void* str_ptr) {
    if (((uint8_t*)str_ptr)[0] < 16) return 0;
    return *(int*)((uint8_t*)str_ptr + 1 + 8); 
}
