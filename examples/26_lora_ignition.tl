-- examples/26_lora_ignition.tl

--@l2c_import: std/esp32.tl
--@l2c_import: std/lora_sx1262.tl
--@l2c_import: std/nvs.tl

--@l2c_import: std/uart.tl
--@l2c_import: std/cmd_queue.tl
--@l2c_import: std/stackstring.tl
--@l2c_import: std/ble_nus.tl

---------------------------------------------------------
-- 副核任务 (Core 1)
---------------------------------------------------------
local function Core1_UartTask()
    UART_init()
    print(" [Core 1] 交互中枢已点火！正在深渊阻塞监听键盘...")
    
    while true do
        local c = UART_read_char()
        if c > 0 then
            -- 【细节修复】：只有可见字符才回显！
            if c >= 32 and c <= 126 then
                print(" [UART]: ", c)
            end
            
            CMD_Push(c)
            -- 跨核闪电突击：踢醒主核！
            C_ESP_IDF.l2c_wake_main_core()
        end
    end
end

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

print(" [L2C] 正在挂载 DIO1 硬件上升沿中断...")
C_ESP_IDF.l2c_setup_dio1_interrupt(EORA_BOARD.DIO1)

-- 点燃第二核心
C_ESP_IDF.l2c_launch_core1(L2C_FuncPtr(Core1_UartTask))

print(" [L2C] 已潜入 433/470MHz 频段，系统进入静默状态...")

OLED_print(2, "RF Status: [ONLINE]")
OLED_print(7, "Sniffing 433MHz...")

-- 点亮蓝牙引擎
BLE_init()
print(" [BLE] 蓝牙广播已开启，设备名: L2C-Mesh")
OLED_print(3, "BLE: [BROADCASTING]")

-- 为 UART 和 BLE 各准备一个解析缓冲，物理隔离防止乱码串台！
local uart_buf = L2C_Buffer(64)
local ble_buf = L2C_Buffer(64)
local uart_str = L2C_Ref(uart_buf)
local ble_str = L2C_Ref(ble_buf)
StackStr_init(uart_str)
StackStr_init(ble_str)

while true do
    C_ESP_IDF.l2c_wait_for_radio()
    SX1262_poll_rx()
    -- 【链路 1】：处理 UART (串口键盘) 命令
    local has_data, c = CMD_Pop()
    while has_data do
        if c == 10 or c == 13 then
            if StackStr_len(uart_str) > 0 then
                print(" [UART-CMD] 收到指令: ", StackStr_get(uart_str))
                StackStr_clear(uart_str)
            end
        else
            StackStr_append_char(uart_str, 64, c)
        end
        has_data, c = CMD_Pop()
    end
    
    -- 【链路 2】：处理 BLE (手机蓝牙) 命令！
    local bc = BLE_pop_char()
    while bc > 0 do
        if bc == 10 or bc == 13 then
            if StackStr_len(ble_str) > 0 then
                local cmd = StackStr_get(ble_str)
                print(" [BLE-CMD] 收到手机无线指令: ", cmd)
                OLED_print(6, cmd) -- 战术雷达上屏！
                StackStr_clear(ble_str)
            end
        else
            StackStr_append_char(ble_str, 64, bc)
        end
        bc = BLE_pop_char()
    end
end