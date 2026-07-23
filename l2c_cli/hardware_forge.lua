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

    -- 📡 1. 嗅探靶向平台，直接生成纯净目标 C 代码（告别 #if defined）
    if bundled_code:match("std/pico%.tl") then
        cfg.arena_size = "8 * 1024"
        cfg.core_count = 2
        cfg.core_id_macro = '#define L2C_GET_CORE_ID() get_core_num()'
        cfg.spinlock_c_decl = [[
            #ifndef L2C_SPINLOCK_DEFINED
            #define L2C_SPINLOCK_DEFINED
            #include "hardware/sync.h"
            static inline void l2c_spinlock_lock(int id) { spin_lock_unsafe_blocking(spin_lock_instance((uint32_t)(id & 31))); }
            static inline void l2c_spinlock_unlock(int id) { spin_unlock_unsafe(spin_lock_instance((uint32_t)(id & 31))); }
            static inline void l2c_launch_core1(void* func_ptr) { multicore_launch_core1((void (*)(void))func_ptr); }
            #define L2C_SPINLOCK_LOCK(id)   l2c_spinlock_lock(id)
            #define L2C_SPINLOCK_UNLOCK(id) l2c_spinlock_unlock(id)
            #endif
        ]]
        print("⚙️  [L2C 兵工厂] Pico 靶向，物理双核与自旋锁已就绪！")
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
        print("⚙️  [L2C 兵工厂] ESP32 靶向，物理双核与自旋锁已就绪！")
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
            static atomic_flag g_l2c_pc_locks[8] = { ATOMIC_FLAG_INIT, ATOMIC_FLAG_INIT, ATOMIC_FLAG_INIT, ATOMIC_FLAG_INIT, ATOMIC_FLAG_INIT, ATOMIC_FLAG_INIT, ATOMIC_FLAG_INIT, ATOMIC_FLAG_INIT };
            static inline void l2c_spinlock_lock(int id) {
                int idx = id & 7;
                while (atomic_flag_test_and_set_explicit(&g_l2c_pc_locks[idx], memory_order_acquire)) {
                    #if defined(__x86_64__) || defined(_M_X64)
                    __builtin_ia32_pause();
                    #elif defined(__aarch64__)
                    __asm__ __volatile__("yield" ::: "memory");
                    #endif
                }
            }
            static inline void l2c_spinlock_unlock(int id) { atomic_flag_clear_explicit(&g_l2c_pc_locks[id & 7], memory_order_release); }
            static inline void l2c_launch_core1(void* func_ptr) { 
                pthread_t t; pthread_create(&t, NULL, (void*(*)(void*))func_ptr, NULL); pthread_detach(t); 
            }
            #define L2C_SPINLOCK_LOCK(id)   l2c_spinlock_lock(id)
            #define L2C_SPINLOCK_UNLOCK(id) l2c_spinlock_unlock(id)
            #endif
        ]]
    end

    -- 🛡️ 2. 无锁切片器：接受 uintptr_t (L2C integer) 直接强转内存指针！
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

    -- 🔗 3. Nelua 中间层 FFI 映射签证
    cfg.nelua_bindings = [[
        local function L2C_Spinlock_Lock(id: integer): void <cimport 'L2C_SPINLOCK_LOCK', nodecl> end
        local function L2C_Spinlock_Unlock(id: integer): void <cimport 'L2C_SPINLOCK_UNLOCK', nodecl> end
        local function l2c_memory_barrier(): void <cimport 'l2c_memory_barrier', nodecl> end
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