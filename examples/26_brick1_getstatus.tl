-- @l2c_import: std/eora_s3.tl
-- @l2c_import: std/lora_sx1262.tl

-- 第一层砖测试：读取 GetStatus (0xC0)
local function test_brick_1_get_status(): boolean
    print("\n============================================")
    print(">> [砖块 1/4] 开始检测 SX1262 物理 SPI & BUSY ...")
    print("============================================")

    -- 1. 设置 BUSY 引脚 (根据你的开发板修改，如 GPIO 4)
    local BUSY_PIN = EORA_BOARD.BUSY
    local CS_PIN = EORA_BOARD.CS
    
    SX1262_init()

    -- 2. 构造 GetStatus (0xC0 0x00) SPI 帧
    local tx_buf = L2C_Buffer(2)
    local rx_buf = L2C_Buffer(2)
    
    C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_buf), 0, 0xC0)
    C_ESP_IDF.l2c_set_byte(L2C_Ref(tx_buf), 1, 0x00)

    -- 3. 拉低 CS 执行传输
    C_ESP_IDF.gpio_set_level(CS_PIN, 0)
    local ret_st = C_ESP_IDF.l2c_sx1262_spi_transfer_safe(L2C_Ref(tx_buf), L2C_Ref(rx_buf), 2)
    C_ESP_IDF.gpio_set_level(CS_PIN, 1)

    -- 4. 打印并解析返回的原始数据
    if ret_st < 0 then
        print("[ERR] SPI 传输失败！错误码: ", ret_st, " (可能 BUSY 引脚死锁或 CS 引脚不对)")
        return false
    end

    local status_byte = C_ESP_IDF.l2c_get_byte(L2C_Ref(rx_buf), 0)
    local chip_mode = (status_byte >> 4) & 0x07
    local cmd_status = (status_byte >> 1) & 0x07

    print(">> [MISO 原始数据] Raw Status Byte: ", status_byte)
    print(">> [芯片模式解析] Chip Mode      : ", chip_mode, " (2=STDBY_RC, 3=STDBY_XOSC, 5=RX, 6=TX)")
    print(">> [指令状态解析] Cmd Status     : ", cmd_status, " (2=Data Available, 3=Cmd Err, 4=Exec Fail)")

    if chip_mode >= 2 and chip_mode <= 6 then
        print("\n [第一层砖·砌筑成功！] ESP32 与 SX1262 底层 SPI/BUSY 完全正常！")
        return true
    else
        print("\n [第一层砖·失败] 返回了无效的 Chip Mode，请检查 SPI MISO/MOSI 连线或芯片供电！")
        return false
    end
end

-- 运行测试
test_brick_1_get_status()