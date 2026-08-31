-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- ==============================================================================
-- L2C 硬件兵工厂 (Hardware Forge)
-- ==============================================================================
local M = {}

-- [核心修复：物理去缩进引擎]
-- 抹除 Lua 多行字符串自带的前导空格，保证生成的 C 源码预处理宏绝对左对齐！
local function align_left(str)
    if type(str) ~= "string" or str == "" then return str end
    -- 将所有以回车后紧跟的空格/Tab 替换为单个回车，并清理首尾空格
    return (str:gsub("\n[ \t]+", "\n"):gsub("^[ \t]+", ""):gsub("[ \t]+$", ""))
end

function M.sniff_and_forge(bundled_code)
    local cfg = {
        arena_size = "10 * 1024 * 1024",
        core_count = 8,
        core_id_macro = "",
        spinlock_c_decl = "",
        spsc_c_decl = "",
        nelua_bindings = ""
    }

    --  1. 嗅探靶向平台，直接生成纯净目标 C 代码（告别 #if defined）
    if bundled_code:match("std/pico%.tl") then
        cfg.arena_size = "8 * 1024"
        cfg.core_count = 2
        cfg.core_id_macro = '#define L2C_GET_CORE_ID() get_core_num()'
        cfg.spinlock_c_decl = [[
            #ifndef L2C_SPINLOCK_DEFINED
            #define L2C_SPINLOCK_DEFINED
            #include "hardware/sync.h"
            #include "hardware/dma.h"
            #include "hardware/irq.h"

            static inline void l2c_spinlock_lock(int id) { spin_lock_unsafe_blocking(spin_lock_instance((uint32_t)(id & 31))); }
            static inline void l2c_spinlock_unlock(int id) { spin_unlock_unsafe(spin_lock_instance((uint32_t)(id & 31))); }
            static inline void l2c_launch_core1(void* func_ptr) { multicore_launch_core1((void (*)(void))func_ptr); }

            // [DMA 硬件泵引擎]：死死锁定 8000Hz 时钟，建立 DREQ 物理握手！
            static inline void l2c_pico_adc_dma_start(int dma_chan, uintptr_t buf_ptr, int sample_count, void* isr_func) {
                adc_init();
                adc_gpio_init(26);
                adc_select_input(0);
                adc_fifo_setup(true, false, 1, false, false);
                // 修复核心：第二个参数改为 true！激活 ADC 向 DMA 发送数据请求 (DREQ)！
                adc_fifo_setup(true, true, 1, false, false);
                adc_set_clkdiv(5999); // 48MHz / 8000Hz = 6000 (分频器填 6000-1)

                dma_channel_config c = dma_channel_get_default_config(dma_chan);
                channel_config_set_transfer_data_size(&c, DMA_SIZE_16); // ADC 读出是 12bit，占 16bit 空间
                channel_config_set_read_increment(&c, false);
                channel_config_set_write_increment(&c, true);
                channel_config_set_dreq(&c, DREQ_ADC); // DREQ 握手：每采样一个点，通知 DMA 搬运一次！

                dma_channel_configure(dma_chan, &c, (void*)buf_ptr, &adc_hw->fifo, sample_count, false);

                // 挂载硬件中断
                irq_set_exclusive_handler(DMA_IRQ_0, (irq_handler_t)isr_func);
                irq_set_enabled(DMA_IRQ_0, true);
                dma_channel_set_irq0_enabled(dma_chan, true);
                dma_channel_start(dma_chan);
                adc_run(true);
            }
            
            // 新增利器：专门用于读取 DMA 紧凑打包的 16位 (uint16_t) 物理内存！
            static inline int l2c_read_adc_buf16(uintptr_t arr_ptr, int idx) { 
                return ((uint16_t*)(void*)arr_ptr)[idx]; 
            }

            // [DMA 引擎重置]：在中断中调用，清空中断标志并开启下一轮搬运
            static inline void l2c_pico_dma_irq_clear_and_restart(int dma_chan, uintptr_t buf_ptr) {
                dma_hw->ints0 = 1u << dma_chan; // 清除中断标志
                dma_channel_set_write_addr(dma_chan, (void*)buf_ptr, true); // 重新给定写地址并触发
            }

            #define L2C_SPINLOCK_LOCK(id)   l2c_spinlock_lock(id)
            #define L2C_SPINLOCK_UNLOCK(id) l2c_spinlock_unlock(id)
            #endif
        ]]
        
        print("  [L2C 兵工厂] Pico 靶向，物理双核与自旋锁已就绪！")
    elseif bundled_code:match("std/esp32%.tl") or bundled_code:match("std/freertos%.tl") then
        cfg.arena_size = "16 * 1024"
        cfg.core_count = 2
        cfg.core_id_macro = '#define L2C_GET_CORE_ID() xPortGetCoreID()'
        cfg.spinlock_c_decl = [[
            #ifndef L2C_SPINLOCK_DEFINED
            #define L2C_SPINLOCK_DEFINED
            #include <stdatomic.h>
            // [核心修复：64 字节 Cache Line 物理隔离，彻底粉碎 False Sharing 性能风暴]
            typedef union { atomic_flag lock; uint8_t _pad[64]; } l2c_aligned_lock_t;
            static l2c_aligned_lock_t g_l2c_locks[8] = {
                {ATOMIC_FLAG_INIT}, {ATOMIC_FLAG_INIT}, {ATOMIC_FLAG_INIT}, {ATOMIC_FLAG_INIT},
                {ATOMIC_FLAG_INIT}, {ATOMIC_FLAG_INIT}, {ATOMIC_FLAG_INIT}, {ATOMIC_FLAG_INIT}
            };
            static inline void l2c_spinlock_lock(int id) { while (atomic_flag_test_and_set_explicit(&g_l2c_locks[id & 7].lock, memory_order_acquire)) { asm volatile("nop"); } }
            static inline void l2c_spinlock_unlock(int id) { __sync_synchronize(); atomic_flag_clear_explicit(&g_l2c_locks[id & 7].lock, memory_order_release); }
            static inline void l2c_launch_core1(void* func_ptr) { xTaskCreatePinnedToCore((TaskFunction_t)func_ptr, "c1", 8192, NULL, 1, NULL, 1); }
            #define L2C_SPINLOCK_LOCK(id)   l2c_spinlock_lock(id)
            #define L2C_SPINLOCK_UNLOCK(id) l2c_spinlock_unlock(id)

            // =========================================================================
            // [L2C 射频引擎]：ESP-IDF 极速 SPI 底层驱动 (SX1262 专用)
            // =========================================================================

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
            // L2C 0-GC 战术雷达副屏驱动 (SSD1306 I2C)
            // =========================================================================

            #include "driver/i2c.h"
            #include <string.h>
            #include <stdio.h>

            #define I2C_MASTER_NUM 0
            #define OLED_ADDR 0x3C

            // 极简 5x8 ASCII 物理字库 (只占区区 480 字节 ROM)
            static const uint8_t l2c_font5x8[][5] = {
                {0x00,0x00,0x00,0x00,0x00}, {0x00,0x00,0x4F,0x00,0x00}, {0x00,0x07,0x00,0x07,0x00},
                {0x14,0x7F,0x14,0x7F,0x14}, {0x24,0x2A,0x7F,0x2A,0x12}, {0x23,0x13,0x08,0x64,0x62},
                {0x36,0x49,0x55,0x22,0x50}, {0x00,0x05,0x03,0x00,0x00}, {0x00,0x1C,0x22,0x41,0x00},
                {0x00,0x41,0x22,0x1C,0x00}, {0x14,0x08,0x3E,0x08,0x14}, {0x08,0x08,0x3E,0x08,0x08},
                {0x00,0x50,0x30,0x00,0x00}, {0x08,0x08,0x08,0x08,0x08}, {0x00,0x60,0x60,0x00,0x00},
                {0x20,0x10,0x08,0x04,0x02}, {0x3E,0x51,0x49,0x45,0x3E}, {0x00,0x42,0x7F,0x40,0x00},
                {0x42,0x61,0x51,0x49,0x46}, {0x21,0x41,0x45,0x4B,0x31}, {0x18,0x14,0x12,0x7F,0x10},
                {0x27,0x45,0x45,0x45,0x39}, {0x3C,0x4A,0x49,0x49,0x30}, {0x01,0x71,0x09,0x05,0x03},
                {0x36,0x49,0x49,0x49,0x36}, {0x06,0x49,0x49,0x29,0x1E}, {0x00,0x36,0x36,0x00,0x00},
                {0x00,0x56,0x36,0x00,0x00}, {0x08,0x14,0x22,0x41,0x00}, {0x14,0x14,0x14,0x14,0x14},
                {0x00,0x41,0x22,0x14,0x08}, {0x02,0x01,0x51,0x09,0x06}, {0x32,0x49,0x79,0x41,0x3E},
                {0x7E,0x11,0x11,0x11,0x7E}, {0x7F,0x49,0x49,0x49,0x36}, {0x3E,0x41,0x41,0x41,0x22},
                {0x7F,0x41,0x41,0x22,0x1C}, {0x7F,0x49,0x49,0x49,0x41}, {0x7F,0x09,0x09,0x09,0x01},
                {0x3E,0x41,0x49,0x49,0x7A}, {0x7F,0x08,0x08,0x08,0x7F}, {0x00,0x41,0x7F,0x41,0x00},
                {0x20,0x40,0x41,0x3F,0x01}, {0x7F,0x08,0x14,0x22,0x41}, {0x7F,0x40,0x40,0x40,0x40},
                {0x7F,0x02,0x0C,0x02,0x7F}, {0x7F,0x04,0x08,0x10,0x7F}, {0x3E,0x41,0x41,0x41,0x3E},
                {0x7F,0x09,0x09,0x09,0x06}, {0x3E,0x41,0x51,0x21,0x5E}, {0x7F,0x09,0x19,0x29,0x46},
                {0x46,0x49,0x49,0x49,0x31}, {0x01,0x01,0x7F,0x01,0x01}, {0x3F,0x40,0x40,0x40,0x3F},
                {0x1F,0x20,0x40,0x20,0x1F}, {0x3F,0x40,0x38,0x40,0x3F}, {0x63,0x14,0x08,0x14,0x63},
                {0x07,0x08,0x70,0x08,0x07}, {0x61,0x51,0x49,0x45,0x43}, {0x00,0x7F,0x41,0x41,0x00},
                {0x02,0x04,0x08,0x10,0x20}, {0x00,0x41,0x41,0x7F,0x00}, {0x04,0x02,0x01,0x02,0x04},
                {0x40,0x40,0x40,0x40,0x40}, {0x00,0x01,0x02,0x04,0x00}, {0x20,0x54,0x54,0x54,0x78},
                {0x7F,0x48,0x44,0x44,0x38}, {0x38,0x44,0x44,0x44,0x20}, {0x38,0x44,0x44,0x48,0x7F},
                {0x38,0x54,0x54,0x54,0x18}, {0x08,0x7E,0x09,0x01,0x02}, {0x0C,0x52,0x52,0x52,0x3E},
                {0x7F,0x08,0x04,0x04,0x78}, {0x00,0x44,0x7D,0x40,0x00}, {0x20,0x40,0x44,0x3D,0x00},
                {0x7F,0x10,0x28,0x44,0x00}, {0x00,0x41,0x7F,0x40,0x00}, {0x7C,0x04,0x18,0x04,0x78},
                {0x7C,0x08,0x04,0x04,0x78}, {0x38,0x44,0x44,0x44,0x38}, {0x7C,0x14,0x14,0x14,0x08},
                {0x08,0x14,0x14,0x18,0x7C}, {0x7C,0x08,0x04,0x04,0x08}, {0x48,0x54,0x54,0x54,0x20},
                {0x04,0x3F,0x44,0x40,0x20}, {0x3C,0x40,0x40,0x20,0x7C}, {0x1C,0x20,0x40,0x20,0x1C},
                {0x3C,0x40,0x30,0x40,0x3C}, {0x44,0x28,0x10,0x28,0x44}, {0x0C,0x50,0x50,0x50,0x3C},
                {0x44,0x64,0x54,0x4C,0x44}, {0x00,0x08,0x36,0x41,0x00}, {0x00,0x00,0x7F,0x00,0x00},
                {0x00,0x41,0x36,0x08,0x00}, {0x10,0x08,0x08,0x10,0x08}, {0x00,0x00,0x00,0x00,0x00}
            };

            static inline void l2c_oled_init(int sda, int scl) {
                i2c_config_t conf = {
                    .mode = I2C_MODE_MASTER, .sda_io_num = sda, .scl_io_num = scl,
                    .sda_pullup_en = GPIO_PULLUP_ENABLE, .scl_pullup_en = GPIO_PULLUP_ENABLE,
                    .master.clk_speed = 400000
                };
                i2c_param_config(I2C_MASTER_NUM, &conf);
                i2c_driver_install(I2C_MASTER_NUM, conf.mode, 0, 0, 0);

                // SSD1306 魔法开机序列 (0x00代表指令)
                uint8_t cmds[] = {
                    0x00, 0xAE, 0xD5, 0x80, 0xA8, 0x3F, 0xD3, 0x00, 0x40, 0x8D, 0x14, 
                    0x20, 0x00, 0xA1, 0xC8, 0xDA, 0x12, 0x81, 0xCF, 0xD9, 0xF1, 
                    0xDB, 0x40, 0xA4, 0xA6, 0xAF
                };
                i2c_master_write_to_device(I2C_MASTER_NUM, OLED_ADDR, cmds, sizeof(cmds), 100);
            }

            // 0-GC 极速画线 (line: 0~7)
            static inline void l2c_oled_print(int line, const char* str) {
                if (line < 0 || line > 7 || !str) return;
                
                // 设置光标位置指令
                uint8_t pos_cmd[] = {0x00, 0xB0 | line, 0x00, 0x10};
                i2c_master_write_to_device(I2C_MASTER_NUM, OLED_ADDR, pos_cmd, 4, 10);

                // 开始连续刷入数据 (0x40代表数据)
                uint8_t data[128 + 1] = {0x40}; // 第一字节是标志，后面128字节是显存
                int ptr = 1;
                while (*str && ptr < 128) {
                    int char_idx = *str - 32; // ASCII 偏移
                    if (char_idx < 0 || char_idx > 95) char_idx = 0;
                    for (int i = 0; i < 5 && ptr < 128; i++) {
                        data[ptr++] = l2c_font5x8[char_idx][i];
                    }
                    if (ptr < 128) data[ptr++] = 0x00; // 字间距
                    str++;
                }
                // 空白填充剩下的屏幕，彻底扫除旧字符残影！
                while (ptr < 129) { data[ptr++] = 0x00; }
                
                i2c_master_write_to_device(I2C_MASTER_NUM, OLED_ADDR, data, 129, 100);
            }

            static inline void l2c_oled_print_num(int line, const char* prefix, int num) {
                char buf[32]; // 在 C 函数栈上开辟 32 字节，离开瞬间销毁
                snprintf(buf, sizeof(buf), "%s%d", prefix, num);
                l2c_oled_print(line, buf);
            }

            // =========================================================================
            // L2C 0-GC 非易失性存储引擎 (NVS)
            // =========================================================================

            #include "nvs_flash.h"
            #include "nvs.h"

            // 全局静态 NVS 句柄
            static nvs_handle_t g_l2c_nvs_handle;

            static inline void l2c_nvs_init(void) {
                // 初始化默认的 NVS 分区
                esp_err_t err = nvs_flash_init();
                // 物理防漏水：如果遇到版本不匹配或没有空闲页，直接物理擦除后重建！
                if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
                    nvs_flash_erase();
                    err = nvs_flash_init();
                }
                // 打开名为 "storage" 的命名空间，权限为读写
                nvs_open("storage", NVS_READWRITE, &g_l2c_nvs_handle);
            }

            // 0-GC 极速读取 (带默认值兜底)
            static inline int32_t l2c_nvs_get_int(const char* key, int32_t default_val) {
                int32_t val = 0;
                esp_err_t err = nvs_get_i32(g_l2c_nvs_handle, key, &val);
                if (err != ESP_OK) return default_val;
                return val;
            }

            // 0-GC 极速写入 (写入后自动提交到物理 Flash)
            static inline void l2c_nvs_set_int(const char* key, int32_t val) {
                nvs_set_i32(g_l2c_nvs_handle, key, val);
                nvs_commit(g_l2c_nvs_handle);
            }

            #endif
        ]]
        print("  [L2C 兵工厂] ESP32 靶向，物理双核与自旋锁已就绪！")
    else
        cfg.core_id_macro = [[
            #include <stdint.h>
            static _Thread_local int g_l2c_thread_id = -1;
            static int g_l2c_next_thread_id = 0;
            static inline int l2c_get_pc_core_id(void) {
                if (g_l2c_thread_id == -1) {
                    g_l2c_thread_id = __atomic_fetch_add(&g_l2c_next_thread_id, 1, __ATOMIC_RELAXED) % 8;
                }
                return g_l2c_thread_id;
            }
            #define L2C_GET_CORE_ID() l2c_get_pc_core_id()
        ]]
        cfg.spinlock_c_decl = [[
            #ifndef L2C_SPINLOCK_DEFINED
            #define L2C_SPINLOCK_DEFINED
            #include <stdatomic.h>
            #include <pthread.h>
            // [核心修复：64 字节 Cache Line 物理隔离，保护 x86_64/ARM64 极速总线]
             typedef union { atomic_flag lock; uint8_t _pad[64]; } l2c_aligned_lock_t;
            static l2c_aligned_lock_t g_l2c_pc_locks[8] = {
                {ATOMIC_FLAG_INIT}, {ATOMIC_FLAG_INIT}, {ATOMIC_FLAG_INIT}, {ATOMIC_FLAG_INIT},
                {ATOMIC_FLAG_INIT}, {ATOMIC_FLAG_INIT}, {ATOMIC_FLAG_INIT}, {ATOMIC_FLAG_INIT}
            };
            static inline void l2c_spinlock_lock(int id) {
                while (atomic_flag_test_and_set_explicit(&g_l2c_pc_locks[id & 7].lock, memory_order_acquire)) {
                    #if defined(__x86_64__) || defined(_M_X64)
                    __builtin_ia32_pause();
                    #elif defined(__aarch64__)
                    __asm__ __volatile__("yield" ::: "memory");
                    #endif
                }
            }
            static inline void l2c_spinlock_unlock(int id) { 
                __sync_synchronize(); atomic_flag_clear_explicit(&g_l2c_pc_locks[id & 7].lock, memory_order_release); 
            }
            static void* l2c_pthread_wrapper(void* arg) {
                void (*func)(void) = (void (*)(void))arg;
                func();
                return NULL;
            }
            // [核心修复] 强制注入 8MB 栈空间，粉碎 Musl 默认的 128KB 爆栈陷阱！
            static inline void l2c_launch_core1(void* func_ptr) { 
                pthread_t t; 
                pthread_attr_t attr;
                pthread_attr_init(&attr);
                pthread_attr_setstacksize(&attr, 8 * 1024 * 1024);
                pthread_create(&t, &attr, l2c_pthread_wrapper, func_ptr); 
                pthread_attr_destroy(&attr);
                pthread_detach(t); 
            }
            #define L2C_SPINLOCK_LOCK(id) l2c_spinlock_lock(id)
            #define L2C_SPINLOCK_UNLOCK(id) l2c_spinlock_unlock(id)
            #endif
        ]]
    end

    --  2. 无锁切片器：接受 uintptr_t (L2C integer) 直接强转内存指针！
    cfg.spsc_c_decl = [[
        #ifndef L2C_SPSC_DEFINED
        #define L2C_SPSC_DEFINED
        #include <stdint.h>
        #include <stddef.h>
        // [核心修复：注入 volatile 防御 -O3 循环不变量提升 (LICM) 死锁]
        static inline ptrdiff_t l2c_spsc_read_arr(uintptr_t arr_ptr, int idx) { return ((volatile ptrdiff_t*)(void*)arr_ptr)[idx]; }
        static inline void l2c_spsc_write_arr(uintptr_t arr_ptr, int idx, ptrdiff_t val) { ((volatile ptrdiff_t*)(void*)arr_ptr)[idx] = val; }
        static inline void l2c_memory_barrier(void) { __sync_synchronize(); }
        #endif
    ]]

    --  3. Nelua 中间层 FFI 映射签证
    cfg.nelua_bindings = [[
        local function L2C_Spinlock_Lock(id: integer): void <cimport 'L2C_SPINLOCK_LOCK', nodecl> end
        local function L2C_Spinlock_Unlock(id: integer): void <cimport 'L2C_SPINLOCK_UNLOCK', nodecl> end
        -- 核心修复：大小写对齐！打通真实物理内存屏障！
        local function L2C_Memory_Barrier(): void <cimport 'l2c_memory_barrier', nodecl> end
        local function l2c_spsc_read_arr(arr_ptr: integer, idx: integer): integer <cimport 'l2c_spsc_read_arr', nodecl> end
        local function l2c_spsc_write_arr(arr_ptr: integer, idx: integer, val: integer): void <cimport 'l2c_spsc_write_arr', nodecl> end
    ]]

    return cfg
end

-- 组装函数：安全拼接，规避 % 解析炸弹
function M.assemble_system(cfg, deps, nelua_code)
    -- 使用 align_left 将模板自身彻底左对齐
    local header_template = align_left([==[
        ## pragma { gc = 'none' }
        ##[[
        cemitdecl([=[
        #ifndef L2C_GET_CORE_ID
        %s
        #endif
        %s
        %s
        ]=])
        ]]

        %s
        require 'allocators.arena'
        %s

        local function L2C_GET_CORE_ID(): integer <cimport, nodecl> end

        local L2C_ArenaType = @ArenaAllocator(%s)
        global my_arenas: [%d]L2C_ArenaType
        
        local function L2C_Get_Arena(): *L2C_ArenaType <inline>
        return &my_arenas[L2C_GET_CORE_ID()]
        end
    ]==])

    -- 注入前，将所有 C 宏和 Nelua 绑定全部通过物理去缩进引擎过滤，实现降维打击！
    local header = string.format(header_template, 
        align_left(cfg.core_id_macro), 
        align_left(cfg.spinlock_c_decl), 
        align_left(cfg.spsc_c_decl), 
        align_left(deps.cincludes or ""), 
        align_left(cfg.nelua_bindings), 
        cfg.arena_size, cfg.core_count
    )

    return header .. "\n\n" .. nelua_code
end

return M