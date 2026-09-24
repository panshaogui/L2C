// ==============================================================================
// Copyright (c) 2026 Panshaogui | MIT License
// L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
// ==============================================================================

#include "esp_lcd_panel_io.h"
#include "esp_lcd_panel_vendor.h"
#include "esp_lcd_panel_ops.h"
#include "driver/spi_master.h"
#include "driver/gpio.h"
#include "esp_err.h"

#include "esp_camera.h"  // 解析结构体必备
#include "esp_heap_caps.h"
#include "img_converters.h" // 借用硬件优化的解码引擎
#include "freertos/semphr.h" // [新增] 引入红绿灯机制

// 微雪板子绝对引脚
#define LCD_HOST    SPI2_HOST
#define SPI_PIN_MOSI 38
#define SPI_PIN_CLK  39
#define SPI_PIN_MISO 40
#define LCD_PIN_CS   45
#define LCD_PIN_DC   42
#define LCD_PIN_RST  0
#define LCD_PIN_BL   1

static esp_lcd_panel_handle_t g_panel_handle = NULL;
static SemaphoreHandle_t g_lcd_trans_sem = NULL;

static bool notify_lcd_trans_done(esp_lcd_panel_io_handle_t panel_io, esp_lcd_panel_io_event_data_t *edata, void *user_ctx) {
    BaseType_t need_yield = pdFALSE;
    xSemaphoreGiveFromISR(g_lcd_trans_sem, &need_yield);
    return (need_yield == pdTRUE);
}

int l2c_lcd_init() {
    if (g_panel_handle) return 1;
    g_lcd_trans_sem = xSemaphoreCreateBinary();

    gpio_set_direction(LCD_PIN_BL, GPIO_MODE_OUTPUT);
    gpio_set_level(LCD_PIN_BL, 1);

    spi_bus_config_t buscfg = {
        .sclk_io_num = SPI_PIN_CLK,
        .mosi_io_num = SPI_PIN_MOSI,
        .miso_io_num = SPI_PIN_MISO,
        .quadwp_io_num = -1,
        .quadhd_io_num = -1,
        .max_transfer_sz = 320 * 240 * 2 
    };
    esp_err_t ret = spi_bus_initialize(LCD_HOST, &buscfg, SPI_DMA_CH_AUTO);
    if (ret != ESP_OK && ret != ESP_ERR_INVALID_STATE) return 0;

    esp_lcd_panel_io_handle_t io_handle = NULL;
    esp_lcd_panel_io_spi_config_t io_config = {
        .dc_gpio_num = LCD_PIN_DC,
        .cs_gpio_num = LCD_PIN_CS,
        .pclk_hz = 40 * 1000 * 1000,
        .lcd_cmd_bits = 8,
        .lcd_param_bits = 8,
        .spi_mode = 0,
        .trans_queue_depth = 10,
        .on_color_trans_done = notify_lcd_trans_done,
    };
    esp_lcd_new_panel_io_spi((esp_lcd_spi_bus_handle_t)LCD_HOST, &io_config, &io_handle);

    esp_lcd_panel_dev_config_t panel_config = {
        .reset_gpio_num = LCD_PIN_RST,
        .rgb_endian = LCD_RGB_ENDIAN_RGB, 
        .bits_per_pixel = 16,             
    };
    esp_lcd_new_panel_st7789(io_handle, &panel_config, &g_panel_handle);
    esp_lcd_panel_reset(g_panel_handle);
    esp_lcd_panel_init(g_panel_handle);
    
    // ==========================================================
    // [长官亲测的真理配置] 硬件切轴横屏 + 镜像修正
    // ==========================================================
    esp_lcd_panel_invert_color(g_panel_handle, true); 
    esp_lcd_panel_swap_xy(g_panel_handle, true);     
    esp_lcd_panel_mirror(g_panel_handle, true, false); 
    // esp_lcd_panel_swap_xy(g_panel_handle, false);       // [关闭切轴]
    // esp_lcd_panel_mirror(g_panel_handle, false, false); // [关闭镜像]

    esp_lcd_panel_disp_on_off(g_panel_handle, true);
    return 1;
}

// ==========================================================
// 0-GC Motion-JPEG 实时秒解直通管道 (彻底免疫错位撕裂)
// ==========================================================
void l2c_lcd_draw_cam_frame(void* fb_ptr) {
    if (!g_panel_handle || !fb_ptr) return;
    camera_fb_t *fb = (camera_fb_t*)fb_ptr;

    // 1. JPEG 原始解压池
    static uint8_t* rgb_buf = NULL;
    if (!rgb_buf) {
        rgb_buf = (uint8_t*)heap_caps_malloc(320 * 240 * 2, MALLOC_CAP_SPIRAM);
        if (!rgb_buf) return;
    }

    // 2. 伪装池：尺寸必须是 320x240！(迎合 DMA 的强行步幅，绝不产生麻花！)
    static uint16_t* b_buf = NULL;
    if (!b_buf) {
        b_buf = (uint16_t*)heap_caps_malloc(320 * 240 * 2, MALLOC_CAP_SPIRAM);
        if (!b_buf) return;
    }

    if (!jpg2rgb565(fb->buf, fb->len, rgb_buf, JPG_SCALE_NONE)) return;
    uint16_t* cam = (uint16_t*)rgb_buf;

    // 3. [终极数学魔法] 逆时针 90 度 (CCW90) + 中央裁切 
    // 将摄像头的 240x240 画面，以逆时针 90 度的姿态，画入 320x240 缓冲区的左侧！
    for (int y_B = 0; y_B < 240; y_B++) {
        for (int x_B = 0; x_B < 320; x_B++) {
            if (x_B < 240) {
                // 坐标反演：从源图像提取像素
                // 源图像的 X = 279 - y_B (相当于逆时针转置并加入了 40 像素的裁切偏移)
                // 源图像的 Y = x_B
                uint16_t c = cam[x_B * 320 + (279 - y_B)];
                
                // 色彩洗影 (去彩色墨水)
                b_buf[y_B * 320 + x_B] = (c >> 8) | (c << 8);
            } else {
                // 多出来的 80 像素宽度，填为纯黑！
                // 等硬件 CW90 旋转后，这块黑色刚好会垫在屏幕的最下方！
                b_buf[y_B * 320 + x_B] = 0x0000;
            }
        }
    }

    // 4. 将这份 320x240 的“毒药”喂给硬件！
    // 硬件会把它顺时针旋转 90 度，吐出来的将是一幅绝对正向、上方监控、下方黑屏的完美画布！
    esp_lcd_panel_draw_bitmap(g_panel_handle, 0, 0, 320, 240, b_buf);
    xSemaphoreTake(g_lcd_trans_sem, portMAX_DELAY);
}