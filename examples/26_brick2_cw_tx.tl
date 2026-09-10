-- @l2c_import: std/eora_s3.tl
-- @l2c_import: std/lora_sx1262.tl

-- 第二层砖测试：CW 连续波发射（物理 RF 通路测试）
print("\n============================================")
print(">> [砖块 2/4] 启动 SX1262 470.375MHz CW 连续波发射 ...")
print("============================================")

SX1262_init()

-- 1. 切换至 Standby RC
print("[SX1262] 1. 切换至 Standby RC 模式 (0x80)...")
if C_ESP_IDF.l2c_sx1262_wait_busy() then
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
    C_ESP_IDF.l2c_sx1262_spi_xfer_2b(0x80, 0x00) 
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
end
C_ESP_IDF.vTaskDelay(1)

-- 2. 设置数据包类型为 LoRa
print("[SX1262] 2. 设置数据包类型为 LoRa (0x8A)...")
SX1262_send_cmd2(0x8A, 0x01) 

-- 3. 设置射频频率
print("[SX1262] 3. 精确锁频至 470.375 MHz (0x86)...")
SX1262_send_cmd5(0x86, 0x1D, 0x66, 0x00, 0x00)

-- 4. 配置 PA 和 TX 参数
print("[SX1262] 4. 配置 PA +22dBm 强力输出 (0x95 & 0x8E)...")
SX1262_send_cmd5(0x95, 0x04, 0x07, 0x00, 0x01)

local buf_txp = L2C_Buffer(3)
C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_txp), 0, 0x8E)
C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_txp), 1, 0x16)
C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_txp), 2, 0x04)
if C_ESP_IDF.l2c_sx1262_wait_busy() then
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
    C_ESP_IDF.l2c_sx1262_spi_write_buffer(L2C_Ref(buf_txp), 3)
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
end

-- 5. 【关键补充】配置调制参数 (SF9, BW250, CR4/5)
print("[SX1262] 5. 配置调制参数 ModulationParams (0x8B)...")
SX1262_send_cmd5(0x8B, 0x09, 0x05, 0x01, 0x00)

-- 6. 【关键补充】配置数据包参数 (Preamble 8, Payload 5)
print("[SX1262] 6. 配置数据包参数 PacketParams (0x8C)...")
local buf_pkt = L2C_Buffer(7)
C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pkt), 0, 0x8C)
C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pkt), 1, 0x00)
C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pkt), 2, 0x08) -- Preamble 8
C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pkt), 3, 0x00) 
C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pkt), 4, 0x05) -- Payload Len 5
C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pkt), 5, 0x01) 
C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_pkt), 6, 0x00) 
if C_ESP_IDF.l2c_sx1262_wait_busy() then
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
    C_ESP_IDF.l2c_sx1262_spi_write_buffer(L2C_Ref(buf_pkt), 7)
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
end

-- 7. 启动发射
print("[SX1262] 7. 正在执行 SetTx (0x83) 启动发射...")
local buf_tx = L2C_Buffer(4)
C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_tx), 0, 0x83)
C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_tx), 1, 0x00)
C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_tx), 2, 0x00)
C_ESP_IDF.l2c_set_byte(L2C_Ref(buf_tx), 3, 0x00)
if C_ESP_IDF.l2c_sx1262_wait_busy() then
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
    C_ESP_IDF.l2c_sx1262_spi_write_buffer(L2C_Ref(buf_tx), 4)
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
end

-- 8. 闭环断言：反查物理状态！
C_ESP_IDF.vTaskDelay(2) -- 给芯片 20ms 启动 PA 功放
local rx_val = 0
if C_ESP_IDF.l2c_sx1262_wait_busy() then
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 0)
    rx_val = C_ESP_IDF.l2c_sx1262_spi_xfer_2b(0xC0, 0x00)
    C_ESP_IDF.gpio_set_level(EORA_BOARD.CS, 1)
end

local status_byte = rx_val // 256
local chip_mode = (status_byte >> 4) & 7

if chip_mode == 6 then
    print("  [成功] 芯片已成功切入 TX 模式！(ChipMode: 6)")
else
    print("  [失败] 芯片未切入 TX 模式，当前物理 Mode: ", chip_mode)
end