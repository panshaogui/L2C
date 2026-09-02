// ==============================================================================
// Copyright (c) 2026 Panshaogui | MIT License
// L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
// ==============================================================================

// =========================================================================
// [L2C 射频引擎]：ESP-IDF 极速 SPI 底层驱动 (SX1262 专用)
// =========================================================================

#include <stddef.h>
#include <stdint.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "driver/gpio.h"
#include "esp_attr.h"
#include "driver/spi_master.h"

static spi_device_handle_t g_sx1262_spi_handle;

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

static inline void l2c_sx1262_spi_write_buffer(void* tx_data, int len) {
    spi_transaction_t t = {0};
    t.length = len * 8; 
    t.tx_buffer = tx_data;
    t.rx_buffer = NULL; // 只发不收
    spi_device_polling_transmit(g_sx1262_spi_handle, &t);
}

// [极速探针]：使用 polling (轮询) 模式进行 0-GC 纳秒级读写
static inline void l2c_sx1262_spi_transfer(void* tx_data, void* rx_data, int len) {
    spi_transaction_t t = {0};
    t.length = len * 8; // ESP-IDF 要求长度必须以 bit (位) 为单位！
    t.tx_buffer = tx_data;
    t.rx_buffer = rx_data;
    // 轮询发送！不休眠，死盯总线直到发送完毕！
    spi_device_polling_transmit(g_sx1262_spi_handle, &t);
}

// [核心修复：8-Bit 物理探针，专用于射频报文读写]
static inline void l2c_set_byte(void* ptr, int idx, int val) { ((uint8_t*)ptr)[idx] = (uint8_t)val; }
static inline int l2c_get_byte(void* ptr, int idx) { return (int)(((uint8_t*)ptr)[idx]); }


// =========================================================================
// [L2C 中断引擎]：0-GC 微秒级射频唤醒 (Hardware ISR + Task Notify)
// =========================================================================

static TaskHandle_t g_l2c_main_task_handle = NULL;

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
