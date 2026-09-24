// ==============================================================================
// Copyright (c) 2026 Panshaogui | MIT License
// L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
// ==============================================================================

#include "esp_camera.h"
#include "esp_log.h"
#include <stdio.h> // 需要用到标准文件 IO

// 0-GC 视觉引脚配置 (基于 ESP32-S3-Touch-LCD-2 官方网表校准)
#define CAM_PIN_PWDN    17 // NLCAM0PWDN NLIO17
#define CAM_PIN_RESET   -1 // 硬件悬空或受外部复位控制
#define CAM_PIN_XCLK    8  // NLCAM0XCLK NLIO8
#define CAM_PIN_SIOD    21 // NLTWI0SDA NLIO21 (摄像头 I2C SDA)
#define CAM_PIN_SIOC    16 // NLTWI0CLK NLIO16 (摄像头 I2C SCL)
#define CAM_PIN_D7      2  // NLCAM0D7 NLIO2
#define CAM_PIN_D6      7  // NLCAM0D6 NLIO7
#define CAM_PIN_D5      10 // NLCAM0D5 NLIO10
#define CAM_PIN_D4      14 // NLCAM0D4 NLIO14
#define CAM_PIN_D3      11 // NLCAM0D3 NLIO11
#define CAM_PIN_D2      15 // NLCAM0D2 NLIO15
#define CAM_PIN_D1      13 // NLCAM0D1 NLIO13
#define CAM_PIN_D0      12 // NLCAM0D0 NLIO12
#define CAM_PIN_VSYNC   6  // NLCAM0VSYNC NLIO6
#define CAM_PIN_HREF    4  // NLCAM0HREF NLIO4
#define CAM_PIN_PCLK    9  // NLCAM0PCLK NLIO9

// =========================================================================
// [L2C 视觉引擎] 0-GC 摄像头 DMA 接管模块
// =========================================================================

static inline int l2c_cam_init() {
    camera_config_t config;
    config.ledc_channel = LEDC_CHANNEL_0;
    config.ledc_timer = LEDC_TIMER_0;
    config.pin_d0 = CAM_PIN_D0; config.pin_d1 = CAM_PIN_D1;
    config.pin_d2 = CAM_PIN_D2; config.pin_d3 = CAM_PIN_D3;
    config.pin_d4 = CAM_PIN_D4; config.pin_d5 = CAM_PIN_D5;
    config.pin_d6 = CAM_PIN_D6; config.pin_d7 = CAM_PIN_D7;
    config.pin_xclk = CAM_PIN_XCLK; config.pin_pclk = CAM_PIN_PCLK;
    config.pin_vsync = CAM_PIN_VSYNC; config.pin_href = CAM_PIN_HREF;
    config.pin_sccb_sda = CAM_PIN_SIOD; config.pin_sccb_scl = CAM_PIN_SIOC;
    config.pin_pwdn = CAM_PIN_PWDN; config.pin_reset = CAM_PIN_RESET;

    // [核心防烧毁镇压] 降频至 10MHz，强行分配 2 帧在 PSRAM！
    config.xclk_freq_hz = 10000000; 

    /*
    
    config.pixel_format = PIXFORMAT_RGB565; 
    config.frame_size = FRAMESIZE_QVGA;     // 320x240
    config.jpeg_quality = 12;
    config.fb_count = 2;
    config.fb_location = CAMERA_FB_IN_PSRAM; 
    
    // [终极画面镇压] 绝对不允许中途抓帧！
    // CAMERA_GRAB_LATEST：DMA 在后台永远只保存最完整的最新帧！CPU 拿到的绝对是完美无撕裂的画面！
    config.grab_mode = CAMERA_GRAB_LATEST;

    esp_err_t err = esp_camera_init(&config);
    
    // [OV5640 专属修正] 如果画面颜色不对，或者倒置了，可以在这里告诉传感器的寄存器自己翻转：
    if (err == ESP_OK) {
        sensor_t *s = esp_camera_sensor_get();

        // 如果摄像头物理贴倒是 180 度，直接在传感器端进行硬件翻转！
        s->set_vflip(s, 1);   // 如果画面上下颠倒，取消这行注释
        s->set_hmirror(s, 0); // 如果画面左右相反，取消这行注释
        
    }

    */

    // [降维打击] 强行输出 JPEG 视频流！
    config.pixel_format = PIXFORMAT_JPEG; 
    config.frame_size = FRAMESIZE_QVGA;  // 320x240 
    config.jpeg_quality = 12;            // 极高画质
    
    config.fb_count = 2;
    config.fb_location = CAMERA_FB_IN_PSRAM;
    config.grab_mode = CAMERA_GRAB_LATEST;

    esp_err_t err = esp_camera_init(&config);
    if (err == ESP_OK) {
        sensor_t *s = esp_camera_sensor_get();
        // 修正厂方横向倒焊 180 度的问题
        s->set_vflip(s, 1);   
        s->set_hmirror(s, 0); 
    }

    return (err == ESP_OK) ? 1 : 0;
}

// 释放帧，将显存还给 DMA，让硬件继续抓下一帧
static inline void l2c_cam_return_frame(void* fb_ptr) {
    if (fb_ptr) {
        esp_camera_fb_return((camera_fb_t*)fb_ptr);
    }
}

// [L2C 视觉引擎] 动态传感器方向控制
static inline void l2c_cam_set_dir(int hmirror, int vflip) {
    sensor_t *s = esp_camera_sensor_get();
    if (s) {
        s->set_hmirror(s, hmirror);
        s->set_vflip(s, vflip);
    }
}

static int g_l2c_last_frame_len = 0;

static inline void* l2c_cam_get_frame(void) {
    camera_fb_t *fb = esp_camera_fb_get();
    if (!fb) return NULL;
    g_l2c_last_frame_len = fb->len; // 硬件提取长度瞬间缓存
    return fb;
}

int l2c_cam_get_frame_len(void) {
    return g_l2c_last_frame_len;
}

// =========================================================================
// [L2C 军医法医库] 独立 JPEG 拍照取证引擎
// =========================================================================

// 专用于取证的 JPEG 模式初始化
static inline int l2c_cam_init_jpeg() {
    camera_config_t config;
    config.ledc_channel = LEDC_CHANNEL_0;
    config.ledc_timer = LEDC_TIMER_0;
    config.pin_d0 = CAM_PIN_D0; config.pin_d1 = CAM_PIN_D1;
    config.pin_d2 = CAM_PIN_D2; config.pin_d3 = CAM_PIN_D3;
    config.pin_d4 = CAM_PIN_D4; config.pin_d5 = CAM_PIN_D5;
    config.pin_d6 = CAM_PIN_D6; config.pin_d7 = CAM_PIN_D7;
    config.pin_xclk = CAM_PIN_XCLK; config.pin_pclk = CAM_PIN_PCLK;
    config.pin_vsync = CAM_PIN_VSYNC; config.pin_href = CAM_PIN_HREF;
    config.pin_sccb_sda = CAM_PIN_SIOD; config.pin_sccb_scl = CAM_PIN_SIOC;
    config.pin_pwdn = CAM_PIN_PWDN; config.pin_reset = CAM_PIN_RESET;

    config.xclk_freq_hz = 10000000; 
    
    // [核心变更] 输出格式改为硬件 JPEG，分辨率开到 VGA (640x480) 方便看清细节！
    config.pixel_format = PIXFORMAT_JPEG; 
    config.frame_size = FRAMESIZE_QVGA;    
    config.jpeg_quality = 12; // 质量 (0-63)，越小越清晰
    config.fb_count = 2;
    config.fb_location = CAMERA_FB_IN_PSRAM; 
    config.grab_mode = CAMERA_GRAB_LATEST;

    esp_err_t err = esp_camera_init(&config);
    if (err == ESP_OK) {
        sensor_t *s = esp_camera_sensor_get();
        // 维持咱们之前猜测的 180 度翻转修正
        s->set_vflip(s, 1);   
        s->set_hmirror(s, 0); 
    }
    return (err == ESP_OK) ? 1 : 0;
}

// 0-GC 物理落盘探针：抓拍一帧，直接以二进制流砸进 TF 卡扇区
static inline int l2c_cam_save_jpg(const char* filepath) {
    camera_fb_t *fb = esp_camera_fb_get();
    if (!fb) return 0; // 抓取失败

    FILE *f = fopen(filepath, "wb");
    if (!f) {
        esp_camera_fb_return(fb);
        return -1; // SD 卡文件打开失败
    }
    
    fwrite(fb->buf, 1, fb->len, f);
    fclose(f);
    
    esp_camera_fb_return(fb); // 用完立刻还给 DMA
    return 1;
}

// [致命错误修复] 从 camera_fb_t 结构体中，提取真正的物理像素阵列指针！
void* l2c_cam_get_pixels(void* fb_ptr) {
    if (!fb_ptr) return NULL;
    return ((camera_fb_t*)fb_ptr)->buf;
}