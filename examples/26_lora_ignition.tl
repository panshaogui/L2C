-- examples/26_lora_ignition.tl

--@l2c_import: std/esp32.tl
--@l2c_import: std/lora_sx1262.tl
--@l2c_import: std/nvs.tl 

-- EoRa-S3 默认 OLED 引脚: SDA=18, SCL=17

OLED_init(18, 17)
OLED_clear() 

NVS_init()

local boot_count = NVS_get_int("boot_cnt", 0)
boot_count = boot_count + 1
NVS_set_int("boot_cnt", boot_count)

OLED_print(0, "L2C-Mesh Node v1.0")
OLED_print(1, "===================")
OLED_print(2, "Initializing RF...")

OLED_print_num(6, "Boot Count: ", boot_count)

SX1262_init()
SX1262_setup_meshtastic_sniffer()
SX1262_setup_rx()

print(" [L2C] 已潜入 433MHz 频段，正在凝视 DIO1 中断线...")

OLED_print(2, "RF Status: [ONLINE]")
OLED_print(7, "Sniffing 433MHz...")

while true do
    SX1262_poll_rx()
    C_ESP_IDF.vTaskDelay(1) 
end
