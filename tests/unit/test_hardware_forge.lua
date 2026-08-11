-- ==============================================================================
-- L2C Unit Test: Hardware Forge (硬件宏嗅探与兵工厂注入)
-- ==============================================================================
local forge = require("l2c_cli.hardware_forge")

print("[UNIT] 正在测试 l2c_cli.hardware_forge ...")

--  战术测试 1: 宿主机 (Host) 兜底嗅探
local cfg_host = forge.sniff_and_forge("-- 没有任何特殊 import 的纯业务代码")
assert(cfg_host.core_count == 8, " Host 核心数应默认兜底为 8，而不是 " .. tostring(cfg_host.core_count))
assert(cfg_host.spinlock_c_decl:match("pthread"), " Host 宿主机未正确注入 pthread 相关自旋锁！")

--  战术测试 2: Pico (RP2040) 靶向嗅探
local cfg_pico = forge.sniff_and_forge("-- @l2c_import: std/pico.tl\nlocal a = 1")
assert(cfg_pico.core_count == 2, " Pico 物理核心数被错误识别，应为 2！")
assert(cfg_pico.spinlock_c_decl:match("hardware/sync.h"), " Pico 固件未包含 hardware/sync.h 硬件锁！")
assert(cfg_pico.arena_size == "8 * 1024", " Pico 的 Arena 内存界限未被安全压制到 8KB！")
assert(cfg_pico.spinlock_c_decl:match("DREQ_ADC"), " Pico 的 DMA 硬件泵 DREQ 握手宏丢失！")

--  战术测试 3: ESP32 / FreeRTOS 靶向嗅探
local cfg_esp = forge.sniff_and_forge("-- @l2c_import: std/esp32.tl\n")
assert(cfg_esp.spinlock_c_decl:match("stdatomic.h"), " ESP32 未正确包含 stdatomic 锁！")
assert(cfg_esp.core_id_macro:match("xPortGetCoreID"), " ESP32 获取 Core ID 未映射到 FreeRTOS 接口！")

print(" hardware_forge 嗅探雷达极其敏锐，跨平台靶向注入无误！")
