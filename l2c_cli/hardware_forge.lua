-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- ==============================================================================
-- L2C 硬件兵工厂 (Hardware Forge)
-- ==============================================================================
local M = {}

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
            static atomic_flag g_l2c_locks[8] = {0};
            static inline void l2c_spinlock_lock(int id) { while (atomic_flag_test_and_set_explicit(&g_l2c_locks[id & 7], memory_order_acquire)) { asm volatile("nop"); } }
            static inline void l2c_spinlock_unlock(int id) { __sync_synchronize(); atomic_flag_clear_explicit(&g_l2c_locks[id & 7], memory_order_release); }
            static inline void l2c_launch_core1(void* func_ptr) { xTaskCreatePinnedToCore((TaskFunction_t)func_ptr, "c1", 8192, NULL, 1, NULL, 1); }
            #define L2C_SPINLOCK_LOCK(id)   l2c_spinlock_lock(id)
            #define L2C_SPINLOCK_UNLOCK(id) l2c_spinlock_unlock(id)
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
            static atomic_flag g_l2c_pc_locks[8] = {0};
            static inline void l2c_spinlock_lock(int id) {
                while (atomic_flag_test_and_set_explicit(&g_l2c_pc_locks[id & 7], memory_order_acquire)) {
                    #if defined(__x86_64__) || defined(_M_X64)
                    __builtin_ia32_pause();
                    #elif defined(__aarch64__)
                    __asm__ __volatile__("yield" ::: "memory");
                    #endif
                }
            }
            static inline void l2c_spinlock_unlock(int id) { 
                __sync_synchronize(); atomic_flag_clear_explicit(&g_l2c_pc_locks[id & 7], memory_order_release); 
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
        static inline ptrdiff_t l2c_spsc_read_arr(uintptr_t arr_ptr, int idx) { return ((ptrdiff_t*)(void*)arr_ptr)[idx]; }
        static inline void l2c_spsc_write_arr(uintptr_t arr_ptr, int idx, ptrdiff_t val) { ((ptrdiff_t*)(void*)arr_ptr)[idx] = val; }
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
    local header = string.format([==[
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
    ]==], cfg.core_id_macro, cfg.spinlock_c_decl, cfg.spsc_c_decl, 
        (deps.cincludes or ""), cfg.nelua_bindings, 
        cfg.arena_size, cfg.core_count)

    return header .. nelua_code
end

return M