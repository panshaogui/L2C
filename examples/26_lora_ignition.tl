-- examples/26_lora_ignition.tl

--@l2c_import: std/esp32.tl
--@l2c_import: std/lora_sx1262.tl

-- 【新增：点亮副屏！】
-- T3-S3/EoRa-S3 默认 OLED 引脚: SDA=18, SCL=17

OLED_init(18, 17)
-- 【核心修复：抹除上电宇宙底噪！】
OLED_clear() 
OLED_print(0, "L2C-Mesh Node v1.0")
OLED_print(1, "===================")
OLED_print(2, "Initializing RF...")

-- 点火！初始化 ESP32 底层 SPI，复位芯片，并获取芯片心跳状态码

SX1262_init()
SX1262_setup_meshtastic_sniffer()

-- 切入窃听模式
SX1262_setup_rx()

print(" [L2C] 已潜入 433MHz 频段，正在凝视 DIO1 中断线...")

OLED_print(2, "RF Status: [ONLINE]")
OLED_print(7, "Sniffing 433MHz...")

while true do
    -- 极限轮询：不断探测芯片的 DIO1 引脚
    SX1262_poll_rx()
    
    -- 稍微喘口气，防止把双核 RTOS 饿死触发看门狗
    C_ESP_IDF.vTaskDelay(1) 
end
