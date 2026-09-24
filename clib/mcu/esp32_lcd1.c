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

#include "esp_camera.h" // 必须引入这个，为了解析 camera_fb_t
#include "freertos/semphr.h" // [新增] 引入红绿灯机制
#include "esp_heap_caps.h"

#include "img_converters.h" // 借用 camera 组件内置的硬件级 JPEG 解码器
#include <stdio.h>

#define LCD_HOST    SPI2_HOST
#define LCD_PIXEL_CLOCK_HZ (20 * 1000 * 1000) // 20MHz 稳盘降频

#define LCD_PIN_MOSI 38
#define LCD_PIN_CLK  39
#define SPI_PIN_MISO 40 // 必须接上 MISO，为了给同总线的 SD 卡用！
#define LCD_PIN_CS   45
#define LCD_PIN_DC   42
#define LCD_PIN_RST  0
#define LCD_PIN_BL   1

static esp_lcd_panel_handle_t g_panel_handle = NULL;
static SemaphoreHandle_t g_lcd_trans_sem = NULL; // DMA 传输完毕信号量

// [核心回调] 当 SPI DMA 把最后 1 个 Byte 砸进屏幕时，硬件会呼叫这个函数
static bool notify_lcd_trans_done(esp_lcd_panel_io_handle_t panel_io, esp_lcd_panel_io_event_data_t *edata, void *user_ctx) {
    BaseType_t need_yield = pdFALSE;
    xSemaphoreGiveFromISR(g_lcd_trans_sem, &need_yield); // 亮绿灯！
    return (need_yield == pdTRUE);
}

static inline int l2c_lcd_init() {
    // 0. 创建二进制信号量
    g_lcd_trans_sem = xSemaphoreCreateBinary();

    // 1. 点亮背光
    gpio_config_t bk_gpio_config = {
        .mode = GPIO_MODE_OUTPUT,
        .pin_bit_mask = 1ULL << LCD_PIN_BL
    };
    gpio_config(&bk_gpio_config);
    gpio_set_level(LCD_PIN_BL, 1);

    // 2. 挂载 SPI 极速 DMA 总线
    spi_bus_config_t buscfg = {
        .sclk_io_num = LCD_PIN_CLK,
        .mosi_io_num = LCD_PIN_MOSI,
        .miso_io_num = SPI_PIN_MISO, // <--- 共享生命线
        .quadwp_io_num = -1,
        .quadhd_io_num = -1,
        .max_transfer_sz = 320 * 240 * 2 
    };
    // SPI2_HOST 初始化。如果 SD 卡先初始化过了，这里会报 INVALID_STATE，我们忽略即可
    esp_err_t ret = spi_bus_initialize(LCD_HOST, &buscfg, SPI_DMA_CH_AUTO);
    if (ret != ESP_OK && ret != ESP_ERR_INVALID_STATE) return 0;

    // 3. 挂载 LCD IO 设备，并注入【硬件回调】
    esp_lcd_panel_io_handle_t io_handle = NULL;
    esp_lcd_panel_io_spi_config_t io_config = {
        .dc_gpio_num = LCD_PIN_DC,
        .cs_gpio_num = LCD_PIN_CS,
        .pclk_hz = LCD_PIXEL_CLOCK_HZ,
        .lcd_cmd_bits = 8,
        .lcd_param_bits = 8,
        .spi_mode = 0,
        .trans_queue_depth = 10,
        .on_color_trans_done = notify_lcd_trans_done, // [核心装甲] 绑定回调
    };
    if (esp_lcd_new_panel_io_spi((esp_lcd_spi_bus_handle_t)LCD_HOST, &io_config, &io_handle) != ESP_OK) return 0;

    // 4. 挂载 ST7789 驱动
    esp_lcd_panel_dev_config_t panel_config = {
        .reset_gpio_num = LCD_PIN_RST,
        .rgb_endian = LCD_RGB_ENDIAN_RGB, // 如果颜色反了（比如人脸是蓝色的），改成 LCD_RGB_ENDIAN_RGB
        .bits_per_pixel = 16,             
    };
    if (esp_lcd_new_panel_st7789(io_handle, &panel_config, &g_panel_handle) != ESP_OK) return 0;

    esp_lcd_panel_reset(g_panel_handle);
    esp_lcd_panel_init(g_panel_handle);
    
    
    esp_lcd_panel_invert_color(g_panel_handle, true); 
    /*
    // [维度校准] 强行把屏幕横过来
    esp_lcd_panel_swap_xy(g_panel_handle, true);     
    esp_lcd_panel_mirror(g_panel_handle, true, false);
    */

    // [基线 1] 绝对关闭切轴！屏幕物理宽度就是 240，高度就是 320！
    esp_lcd_panel_swap_xy(g_panel_handle, false);     
    
    // [基线 2] 绝对关闭任何镜像！
    esp_lcd_panel_mirror(g_panel_handle, false, false);

    esp_lcd_panel_disp_on_off(g_panel_handle, true);
    return 1;
}

// 0-GC 极速送显：强制防踩踏！
static inline void l2c_lcd_draw_frame(void* frame_ptr, int width, int height) {
    if (!g_panel_handle || !frame_ptr) return;
    uint8_t* pixels = (uint8_t*)frame_ptr;
    
    // 触发 DMA 搬运
    esp_lcd_panel_draw_bitmap(g_panel_handle, 0, 0, width, height, pixels);
    
    // [核心镇压] CPU 在这里死死卡住！直到屏幕彻底画完，信号量变绿，才允许返回 Teal 脚本！
    // 这样 Teal 脚本里的 Camera_Release 就绝对不可能提前发生！
    xSemaphoreTake(g_lcd_trans_sem, portMAX_DELAY);
}

// =========================================================================
// [L2C 视觉引擎] LCD 物理定标器 (独立测试用)
// =========================================================================

// 全屏填充纯色 (用于校验 RGB/BGR 色彩倒置)
static inline void l2c_lcd_fill_color(int r, int g, int b) {
    if (!g_panel_handle) return;
    // RGB888 转 RGB565
    uint16_t color = ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3);
    // SPI 总线高低字节翻转
    uint16_t swapped_color = (color >> 8) | (color << 8);
    
    // 从 PSRAM 借用一块 150KB 内存作为纯色显存
    uint16_t* buf = (uint16_t*)heap_caps_malloc(320 * 240 * 2, MALLOC_CAP_SPIRAM);
    if (!buf) return;
    for (int i = 0; i < 320 * 240; i++) buf[i] = swapped_color;
    
    esp_lcd_panel_draw_bitmap(g_panel_handle, 0, 0, 320, 240, buf);
    xSemaphoreTake(g_lcd_trans_sem, portMAX_DELAY); // 等待画完
    free(buf);
}

// 局部画方块 (用于校验 X/Y 轴方向与物理原点)
static inline void l2c_lcd_draw_rect(int x, int y, int w, int h, int r, int g, int b) {
    if (!g_panel_handle) return;
    uint16_t color = ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3);
    uint16_t swapped_color = (color >> 8) | (color << 8);
    
    uint16_t* buf = (uint16_t*)heap_caps_malloc(w * h * 2, MALLOC_CAP_SPIRAM);
    if (!buf) return;
    for (int i = 0; i < w * h; i++) buf[i] = swapped_color;
    
    // (x_start, y_start, x_end, y_end)
    esp_lcd_panel_draw_bitmap(g_panel_handle, x, y, x + w, y + h, buf);
    xSemaphoreTake(g_lcd_trans_sem, portMAX_DELAY);
    free(buf);
}

// [L2C 视觉引擎] LCD 控制器 MADCTL 硬件切轴
static inline void l2c_lcd_set_dir(int swap_xy, int mirror_x, int mirror_y) {
    if (!g_panel_handle) return;
    esp_lcd_panel_swap_xy(g_panel_handle, swap_xy ? true : false);
    esp_lcd_panel_mirror(g_panel_handle, mirror_x ? true : false, mirror_y ? true : false);
}

// =========================================================================
// [L2C 视觉引擎] 静态图片显影探针 (用于彻底隔离测试 LCD 渲染通道)
// =========================================================================
static inline int l2c_lcd_draw_jpg_from_sd(const char* filepath) {
    if (!g_panel_handle) return 0;

    FILE* f = fopen(filepath, "rb");
    if (!f) return -1; // 打不开文件

    // 获取 JPEG 文件真实大小
    fseek(f, 0, SEEK_END);
    size_t jpg_size = ftell(f);
    fseek(f, 0, SEEK_SET);

    // 在 PSRAM 分配读取缓冲区
    uint8_t* jpg_buf = (uint8_t*)heap_caps_malloc(jpg_size, MALLOC_CAP_SPIRAM);
    if (!jpg_buf) { fclose(f); return -2; }

    fread(jpg_buf, 1, jpg_size, f);
    fclose(f);

    // 申请 320x240 的纯净 RGB565 显存 (约 150KB)
    uint8_t* rgb_buf = (uint8_t*)heap_caps_malloc(320 * 240 * 2, MALLOC_CAP_SPIRAM);
    if (!rgb_buf) { free(jpg_buf); return -3; }

    // [解除封印] 既然存下来的图已经是 320x240，绝对不能再缩小了！
    // 强制使用 JPG_SCALE_NONE 进行 1:1 像素级原图显影！
    bool decoded = jpg2rgb565(jpg_buf, jpg_size, rgb_buf, JPG_SCALE_NONE);
    free(jpg_buf); // 释放原始压缩包

    if (!decoded) {
        free(rgb_buf);
        return -4; // 解码失败
    }

    // ==========================================================
    // [色彩洗影修复] 强行将 RGB565 的高低字节对调 (Endian Swap)
    // 粉碎“彩色墨水”幻觉！
    // ==========================================================
    uint16_t* pixels = (uint16_t*)rgb_buf;
    for (int i = 0; i < 320 * 240; i++) {
        pixels[i] = (pixels[i] >> 8) | (pixels[i] << 8);
    }

    // [终极物理宣判] 把完美静态的 320x240 RGB 数据砸向屏幕！
    esp_lcd_panel_draw_bitmap(g_panel_handle, 0, 0, 320, 240, rgb_buf);
    xSemaphoreTake(g_lcd_trans_sem, portMAX_DELAY);

    free(rgb_buf);
    return 1;
}

// =========================================================================
// [L2C 视觉引擎] 顺时针 90度 矩阵转置 (CW90)
// 传入: 320x240 原始指针 | 传出: 240x320 竖屏送显
// =========================================================================
void l2c_lcd_draw_cam_cw90(void* fb_ptr) {
    if (!g_panel_handle || !fb_ptr) return;
    
    // 1. 结构体解包，获取真实的物理尺寸！
    camera_fb_t *fb = (camera_fb_t*)fb_ptr;
    int w = fb->width;
    int h = fb->height;
    uint16_t* src = (uint16_t*)fb->buf;

    // 2. 绝对防线：如果尺寸不是 320x240，立刻拦截并报警！绝不花屏！
    if (w != 320 || h != 240) {
        printf("\n ❌ [严重错位] 期待 320x240，但摄像头实际吐出 %dx%d！\n", w, h);
        printf(" -> 请修改 esp32_camera.c 中的 config.frame_size = FRAMESIZE_QVGA;\n\n");
        return;
    }

    // 3. 申请永久的 240x320 竖屏画布
    static uint16_t* dst = NULL;
    if (!dst) {
        dst = (uint16_t*)heap_caps_malloc(240 * 320 * 2, MALLOC_CAP_SPIRAM);
        if (!dst) return;
    }

    // 4. [核心数学魔法] 逆时针 90 度矩阵转置 (CCW90)
    // 目标 X = y
    // 目标 Y = 319 - x
    for (int y = 0; y < 240; y++) {
        for (int x = 0; x < 320; x++) {
            uint16_t color = src[y * 320 + x];
            color = (color >> 8) | (color << 8); // 色彩洗影，恢复真实颜色
            
            // 目标索引 = dst_y * 240 + dst_x
            dst[(319 - x) * 240 + y] = color;
        }
    }

    // 5. 完美送显：竖屏格式 (宽 240, 高 320)
    esp_lcd_panel_draw_bitmap(g_panel_handle, 0, 0, 240, 320, dst);
    xSemaphoreTake(g_lcd_trans_sem, portMAX_DELAY);
}