# 06_l2c_radar.py
import serial
import time

# 请根据实际情况确认您 Mac 上的 Pico 串口号
PORT = '/dev/cu.usbmodem211201'  
BAUD = 115200

def capture_and_render_vcd():
    ser = serial.Serial(PORT, BAUD, timeout=1)
    print("  L2C Tactical Radar listening...")

    while True:
        line = ser.readline().decode('ascii', errors='ignore')
        if ">>> Triggering Memory Dump" in line:
            print(" 捕获到 FPGA 内存倒出信号，正在吸入数据...")
            
            # 连续读取 128 字节纯净二进制数据（对应硬件 128 字节寄存器缓存）
            raw_data = ser.read(128)
            if len(raw_data) < 128:
                print(" 丢包：仅收到", len(raw_data), "字节")
                continue

            # 转换为 VCD (Value Change Dump) 格式
            vcd_filename = f"capture_{int(time.time())}.vcd"
            with open(vcd_filename, "w") as f:
                f.write("$date Today $end\n")
                f.write("$timescale 10ns $end\n") # 假设采样时钟周期
                f.write("$scope module L2C_LogicAnalyzer $end\n")
                f.write("$var wire 8 ! rx_bus $end\n")
                f.write("$upscope $end\n")
                f.write("$enddefinitions $end\n")
                f.write("$dumpvars\n")
                
                # 遍历 128 个采样点生成波形
                for timestamp, byte_val in enumerate(raw_data):
                    # 将字节转为 8 位二进制字符串
                    bin_str = f"b{byte_val:08b}"
                    f.write(f"#{timestamp}\n")
                    f.write(f"{bin_str} !\n")
                    
            print(f" 波形已渲染完成: {vcd_filename}")
            print(" 在 Mac 上使用 'brew install surfer'，然后运行 'surfer {}' 即可查看上帝视角波形！".format(vcd_filename))

if __name__ == '__main__':
    capture_and_render_vcd()