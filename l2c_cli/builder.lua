-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

local tl = require("tl")
local Codegen = require("codegen.core")
local M = {}

function M.build_nelua(bundled_code, deps, input_file)
    local env = tl.init_env()
    local result = tl.process_string(bundled_code, false, env, input_file)
    if #result.syntax_errors > 0 or #result.type_errors > 0 then
        print("❌ Teal 语法/类型检查失败:")
        for _, err in ipairs(result.syntax_errors) do print("  [语法错误]:", err.msg) end
        for _, err in ipairs(result.type_errors) do print("  [类型错误]:", err.msg) end
        local f_dump = io.open(".l2c_error_dump.tl", "w")
        f_dump:write(bundled_code) f_dump:close()
        os.exit(1)
    end

    local engine = Codegen.new()
    local nelua_code = engine:gen(result.ast)
    
    -- 📡 核心降维魔法：靶向智能伸缩与多核隔离注入
    local arena_size = "10 * 1024 * 1024"
    local core_count = 8   -- 🔥 PC HOST 靶向：默认开启 8 线程并发内存池
    
    local core_id_macro = [[
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

    -- 🛡️ 全平台物理级自旋锁底层 C 实现
    local spinlock_c_decl = [=[
        #ifndef L2C_SPINLOCK_DEFINED
        #define L2C_SPINLOCK_DEFINED

        #if defined(PICO_BOARD) || defined(PICO_BUILD)
            #include "hardware/sync.h"
            #include "pico/multicore.h"
            static inline void l2c_spinlock_lock(int id) { spin_lock_unsafe_blocking(spin_lock_instance((uint32_t)(id & 31))); }
            static inline void l2c_spinlock_unlock(int id) { spin_unlock_unsafe(spin_lock_instance((uint32_t)(id & 31))); }
            //  Pico 物理点火
            static inline void l2c_launch_core1(void* func_ptr) { multicore_launch_core1((void (*)(void))func_ptr); }

        #elif defined(ESP_PLATFORM)
            #include "freertos/FreeRTOS.h"
            #include "freertos/task.h"
            static portMUX_TYPE g_l2c_locks[8] = { [0 ... 7] = portMUX_INITIALIZER_UNLOCKED };
            static inline void l2c_spinlock_lock(int id) { taskENTER_CRITICAL(&g_l2c_locks[id & 7]); }
            static inline void l2c_spinlock_unlock(int id) { taskEXIT_CRITICAL(&g_l2c_locks[id & 7]); }
            //  ESP32 物理点火 (绑死 Core 1)
            static inline void l2c_launch_core1(void* func_ptr) { xTaskCreatePinnedToCore((TaskFunction_t)func_ptr, "c1", 8192, NULL, 1, NULL, 1); }

        #else
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
            // PC 线程模拟点火
            static inline void l2c_launch_core1(void* func_ptr) { 
                pthread_t t; 
                pthread_create(&t, NULL, (void*(*)(void*))func_ptr, NULL); 
                pthread_detach(t); 
            }
        #endif

        #define L2C_SPINLOCK_LOCK(id)   l2c_spinlock_lock(id)
        #define L2C_SPINLOCK_UNLOCK(id) l2c_spinlock_unlock(id)

        #endif
    ]=]
    
    if bundled_code:match("std/pico%.tl") then
        arena_size = "32 * 1024"
        core_count = 2
        core_id_macro = '#include "pico/multicore.h"\n#define L2C_GET_CORE_ID() get_core_num()'
        print("⚙️  [L2C 多核雷达] 嗅探到 Pico 靶向，Arena=32KB，物理双核阵列与自旋锁已就绪！")
    elseif bundled_code:match("std/esp32%.tl") or bundled_code:match("std/freertos%.tl") then
        arena_size = "64 * 1024"
        core_count = 2
        core_id_macro = '#include "freertos/FreeRTOS.h"\n#include "freertos/task.h"\n#define L2C_GET_CORE_ID() xPortGetCoreID()'
        print("⚙️  [L2C 多核雷达] 嗅探到 ESP32 靶向，Arena=64KB，物理双核阵列与自旋锁已就绪！")
    end

    -- 🔗 编译中间层 (Nelua) 的 FFI 符号绑定宏
    local spinlock_macro = [[
        local function L2C_Spinlock_Lock(id: integer): void <cimport 'L2C_SPINLOCK_LOCK', nodecl> end
        local function L2C_Spinlock_Unlock(id: integer): void <cimport 'L2C_SPINLOCK_UNLOCK', nodecl> end
]]

    local final_code = "## pragma { gc = 'none' }\n" ..
        "##[[\n" ..
        "cemitdecl([=[\n" ..
        "#ifndef L2C_GET_CORE_ID\n" ..
        core_id_macro .. "\n" ..
        "#endif\n" ..
        spinlock_c_decl .. "\n" ..
        "]=])\n" ..
        "]]\n" ..
        (deps.cincludes or "") .. "\n" ..
        "require 'allocators.arena'\n\n" ..
        spinlock_macro .. "\n" ..
        "-- 引入 C 层的宏，让 Nelua 知道当前跑在哪个核上\n" ..
        "local function L2C_GET_CORE_ID(): integer <cimport, nodecl> end\n\n" ..
        "local L2C_ArenaType = @ArenaAllocator(" .. arena_size .. ")\n" ..
        "global my_arenas: [" .. tostring(core_count) .. "]L2C_ArenaType\n\n" ..
        "--  动态隔离路由：每次分配时实时获取当前核心 ID (防止 SMP 初始化陷阱)！\n" ..
        "local function L2C_Get_Arena(): *L2C_ArenaType <inline>\n" ..
        "  return &my_arenas[L2C_GET_CORE_ID()]\n" ..
        "end\n\n" ..
        nelua_code

    local tmp_file = ".l2c_temp_" .. os.time() .. ".nelua"
    local f_out = io.open(tmp_file, "w")
    f_out:write(final_code) f_out:close()
    return tmp_file
end

return M
