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
        .sclk_io_num = SPI_PIN_CLK, .mosi_io_num = SPI_PIN_MOSI, .miso_io_num = SPI_PIN_MISO,
        .quadwp_io_num = -1, .quadhd_io_num = -1, .max_transfer_sz = 320 * 240 * 2 
    };
    esp_err_t ret = spi_bus_initialize(LCD_HOST, &buscfg, SPI_DMA_CH_AUTO);
    if (ret != ESP_OK && ret != ESP_ERR_INVALID_STATE) return 0;

    esp_lcd_panel_io_handle_t io_handle = NULL;
    esp_lcd_panel_io_spi_config_t io_config = {
        .dc_gpio_num = LCD_PIN_DC, .cs_gpio_num = LCD_PIN_CS, .pclk_hz = 40 * 1000 * 1000,
        .lcd_cmd_bits = 8, .lcd_param_bits = 8, .spi_mode = 0, .trans_queue_depth = 10,
        .on_color_trans_done = notify_lcd_trans_done,
    };
    esp_lcd_new_panel_io_spi((esp_lcd_spi_bus_handle_t)LCD_HOST, &io_config, &io_handle);

    esp_lcd_panel_dev_config_t panel_config = {
        .reset_gpio_num = LCD_PIN_RST, .rgb_endian = LCD_RGB_ENDIAN_RGB, .bits_per_pixel = 16,             
    };
    esp_lcd_new_panel_st7789(io_handle, &panel_config, &g_panel_handle);
    esp_lcd_panel_reset(g_panel_handle);
    esp_lcd_panel_init(g_panel_handle);
    
    // [原生竖屏底盘] 物理宽 240，高 320
    esp_lcd_panel_invert_color(g_panel_handle, true); 
    esp_lcd_panel_swap_xy(g_panel_handle, false);     
    esp_lcd_panel_mirror(g_panel_handle, false, false); 

    esp_lcd_panel_disp_on_off(g_panel_handle, true);
    return 1;
}

// ==========================================================
// [视觉军区] 上方 3/4：240x240 摄像头中央裁切直通！
// ==========================================================
void l2c_lcd_draw_cam_cropped(void* fb_ptr) {
    if (!g_panel_handle || !fb_ptr) return;
    camera_fb_t *fb = (camera_fb_t*)fb_ptr;

    static uint8_t* rgb_buf = NULL;
    static uint16_t* crop_buf = NULL;
    if (!rgb_buf) rgb_buf = (uint8_t*)heap_caps_malloc(320 * 240 * 2, MALLOC_CAP_SPIRAM);
    if (!crop_buf) crop_buf = (uint16_t*)heap_caps_malloc(240 * 240 * 2, MALLOC_CAP_SPIRAM);
    if (!rgb_buf || !crop_buf) return;

    if (!jpg2rgb565(fb->buf, fb->len, rgb_buf, JPG_SCALE_NONE)) return;

    uint16_t* src = (uint16_t*)rgb_buf;

    // 裁切：抛弃左右各 40 像素，留下中央 240！
    for (int y = 0; y < 240; y++) {
        for (int x = 0; x < 240; x++) {
            uint16_t c = src[y * 320 + (x + 40)];
            c = (c >> 8) | (c << 8); // 色彩洗影
            crop_buf[y * 240 + x] = c;
        }
    }

    // 严丝合缝砸向屏幕的 0~240 区域！
    esp_lcd_panel_draw_bitmap(g_panel_handle, 0, 0, 240, 240, crop_buf);
    xSemaphoreTake(g_lcd_trans_sem, portMAX_DELAY);
}