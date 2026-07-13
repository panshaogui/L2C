#ifndef FREERTOS_CONFIG_H
#define FREERTOS_CONFIG_H

/* 1. 核心调度与内存 */
#define configUSE_PREEMPTION                    1
#define configUSE_TICKLESS_IDLE                 0
#define configCPU_CLOCK_HZ                      133000000 // Pico 默认 133MHz
#define configTICK_RATE_HZ                      1000      // 1ms 一个 Tick
#define configMAX_PRIORITIES                    5
#define configMINIMAL_STACK_SIZE                256
#define configMAX_TASK_NAME_LEN                 16
#define configUSE_16_BIT_TICKS                  0
#define configIDLE_SHOULD_YIELD                 1
#define configUSE_TASK_NOTIFICATIONS            1
#define configUSE_MUTEXES                       1
#define configUSE_RECURSIVE_MUTEXES             1
#define configUSE_COUNTING_SEMAPHORES           1
#define configSUPPORT_DYNAMIC_ALLOCATION        1
#define configTOTAL_HEAP_SIZE                   (64 * 1024) // 拨 64KB 内存给 RTOS

/* 🔥 必须配置的 Timers 参数，填补之前的漏缺 */
#define configUSE_TIMERS                        1
#define configTIMER_TASK_PRIORITY               3
#define configTIMER_QUEUE_LENGTH                10
#define configTIMER_TASK_STACK_DEPTH            256

/* 🔥 硬件白皮书：明确告诉 FreeRTOS 咱没有 MPU 和 FPU */
#define configENABLE_MPU                        0
#define configENABLE_FPU                        0
#define configENABLE_TRUSTZONE                  0

/* 2. Hooks 与统计 (禁用以提升极致性能) */
#define configUSE_IDLE_HOOK                     0
#define configUSE_TICK_HOOK                     0
#define configCHECK_FOR_STACK_OVERFLOW          0
#define configUSE_MALLOC_FAILED_HOOK            0
#define configGENERATE_RUN_TIME_STATS           0
#define configUSE_TRACE_FACILITY                0

/* 3. 极其关键：将 FreeRTOS 底层中断映射到 ARM Cortex-M0+ 的标准中断向量上！ */
#define vPortSVCHandler         isr_svcall
#define xPortPendSVHandler      isr_pendsv
#define xPortSysTickHandler     isr_systick

/* ========================================================================= */
/* 🔥 L2C 嵌入式绝杀：开启 API 阀门与 Cortex-M0+ 移植层定义 */
/* ========================================================================= */
#define INCLUDE_vTaskDelay                    1
#define INCLUDE_vTaskDelayUntil               1
#define INCLUDE_vTaskDelete                   1
#define INCLUDE_vTaskPrioritySet              1

// 💡 必须加上这行，显式告诉 FreeRTOS 使用标准的 ARM CM0 移植层
#define configINCLUDE_PLATFORM_H              1

#endif /* FREERTOS_CONFIG_H */
