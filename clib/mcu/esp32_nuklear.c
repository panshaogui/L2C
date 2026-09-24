// ==============================================================================
// Copyright (c) 2026 Panshaogui | MIT License
// L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
// ==============================================================================

#include "esp_heap_caps.h"
#include "esp_lcd_panel_io.h"
#include "esp_lcd_panel_ops.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include <string.h>
#include <math.h> /* 解决 ceil 缺失问题 */
#include "freertos/semphr.h"

static esp_lcd_panel_handle_t g_panel_handle;
static SemaphoreHandle_t g_lcd_trans_sem;

// =========================================================================
// [L2C 视觉引擎] Nuklear IMGUI 配置与实例化
// =========================================================================

/* 1. 功能控制宏：必须严格定义在 nuklear.h 包含之前 */
#define NK_INCLUDE_FIXED_TYPES
#define NK_INCLUDE_STANDARD_IO
#define NK_INCLUDE_STANDARD_VARARGS
#define NK_INCLUDE_DEFAULT_ALLOCATOR
#define NK_INCLUDE_FONT_BAKING
#define NK_INCLUDE_DEFAULT_FONT
#define NK_INCLUDE_VERTEX_BUFFER_OUTPUT /* 关键：彻底暴露 struct nk_user_font_glyph */

/* 2. 核心实现与头文件 */
#define NK_IMPLEMENTATION
#include "nuklear.h"

/* 3. RawFB 后端实现与头文件 */
#define NK_RAWFB_IMPLEMENTATION
#include "nuklear_rawfb.h"

static struct rawfb_context *g_rawfb = NULL;
static uint16_t *g_nk_fb_16 = NULL; 
static void *g_nk_tex_mem = NULL;

// 定义全局 RGB565 法则，供 init 和 resize 共同使用
static struct rawfb_pl g_pl_rgb565 = {
    .bytesPerPixel = 2,
    .rshift = 11, .gshift = 5, .bshift = 0, .ashift = 0,
    .rloss = 3,   .gloss = 2,  .bloss = 3,  .aloss = 8
};

// =========================================================================
// 初始化：以最大极值 (240x320) 开辟 0-GC 水库
// =========================================================================
int l2c_nk_init() {
    if (g_rawfb) return 1;
    
    // 申请最大物理需求显存，终生不释放
    g_nk_fb_16 = (uint16_t*)heap_caps_malloc(240 * 320 * 2, MALLOC_CAP_SPIRAM);
    g_nk_tex_mem = heap_caps_malloc(256 * 1024, MALLOC_CAP_SPIRAM);
    if (!g_nk_fb_16 || !g_nk_tex_mem) return 0;

    // 默认按照全屏 240x320 挂载
    g_rawfb = nk_rawfb_init(g_nk_fb_16, g_nk_tex_mem, 240, 320, 240 * 2, g_pl_rgb565);
    return g_rawfb ? 1 : 0;
}

// =========================================================================
// 动态视口重置：0-GC 秒切全屏/分屏
// =========================================================================
void l2c_nk_resize(int w, int h) {
    if (!g_rawfb) return;
    // 内存依然使用 g_nk_fb_16，只是告诉 Nuklear 画布的逻辑尺寸变了
    nk_rawfb_resize_fb(g_rawfb, g_nk_fb_16, w, h, w * 2, g_pl_rgb565);
}

// =========================================================================
// 带有物理阻断的触觉神经输入 (修复 Release 事件被吞噬死锁)
// =========================================================================
static int last_ui_x = 0;
static int last_ui_y = 0;

void l2c_nk_input(int pressed, int x, int y, int offset_y) {
    if (!g_rawfb) return;

    nk_input_begin(&g_rawfb->ctx);
    
    if (pressed) {
        // 物理阻断：如果按在摄像头区域，Nuklear 无视！
        if (y >= offset_y) {
            last_ui_x = x;
            last_ui_y = y - offset_y; // 坐标降维
            nk_input_motion(&g_rawfb->ctx, last_ui_x, last_ui_y);
            nk_input_button(&g_rawfb->ctx, NK_BUTTON_LEFT, last_ui_x, last_ui_y, 1);
        }
    } else {
        // [核心修复] 手指抬起时，无论坐标是多少，都必须向最后一次触控的位置发送释放信号！
        // 否则 Nuklear 的按钮会永远卡在“按下”状态导致无法触发 Click！
        nk_input_button(&g_rawfb->ctx, NK_BUTTON_LEFT, last_ui_x, last_ui_y, 0);
    }
    
    nk_input_end(&g_rawfb->ctx);
}

// =========================================================================
// 定点空投送显：直接填入屏幕的指定 Y 轴区域
// =========================================================================
void l2c_nk_render(int offset_y, int w, int h) {
    if (!g_rawfb || !g_panel_handle) return;

    // 1. Nuklear 渲染 UI
    nk_rawfb_render(g_rawfb, nk_rgb(40, 40, 40), 1);
    
    // 2. 就地洗影去噪点 (仅处理被使用的 w*h 区域，极速)
    for (int i = 0; i < w * h; i++) {
        uint16_t c = g_nk_fb_16[i];
        g_nk_fb_16[i] = (c >> 8) | (c << 8); 
    }

    // 3. 靶向填补：DMA 将画布严丝合缝地贴在 offset_y 的位置
    esp_lcd_panel_draw_bitmap(g_panel_handle, 0, offset_y, w, offset_y + h, g_nk_fb_16);
    xSemaphoreTake(g_lcd_trans_sem, portMAX_DELAY);
    
    nk_clear(&g_rawfb->ctx);
}

// ... 保持 UI 控件探针不变 (nk_begin, nk_end, etc.) ...
int l2c_nk_begin(const char* title, float x, float y, float w, float h) {
    return nk_begin(&g_rawfb->ctx, title, nk_rect(x, y, w, h), NK_WINDOW_BORDER | NK_WINDOW_TITLE | NK_WINDOW_MOVABLE);
}
void l2c_nk_end() { nk_end(&g_rawfb->ctx); }
void l2c_nk_layout_row_dynamic(float h, int cols) { nk_layout_row_dynamic(&g_rawfb->ctx, h, cols); }
int l2c_nk_button_label(const char* text) { return nk_button_label(&g_rawfb->ctx, text); }
void l2c_nk_label(const char* text) { nk_label(&g_rawfb->ctx, text, NK_TEXT_LEFT); }