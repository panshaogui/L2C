# 26_radar_server.py
import socket
import threading
import sys

# 战术配置
LISTEN_PORT = 8888       # Mac 监听的端口 (接收阵地情报)
TARGET_PORT = 8889       # L2C 节点监听的端口 (接收 Mac 指令)
known_l2c_ip = None      # 自动锁定 L2C 节点的 IP

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(("0.0.0.0", LISTEN_PORT))

# 后台情报监听线程
def listen_loop():
    global known_l2c_ip
    print(f" L2C-Mesh 战术指挥中心已启动，监听 {LISTEN_PORT} 端口...")
    while True:
        try:
            data, addr = s.recvfrom(1024)
            known_l2c_ip = addr[0] # 只要收到一次情报，立刻锁定目标 IP！
            # 优雅地把情报打印出来，并恢复输入提示符
            print(f"\r[情报 | {addr[0]}] {data.decode('utf-8', 'ignore')}\n> ", end="")
        except Exception:
            break

# 启动后台监听线程 (daemon=True 保证随主线程死亡)
t = threading.Thread(target=listen_loop, daemon=True)
t.start()

# 前台指令下发主循环 (自带 Ctrl+C 防御)
try:
    while True:
        cmd = input("> ")
        if cmd.strip():
            if known_l2c_ip:
                # 拔枪射击！向 L2C 节点下发指令！
                s.sendto(cmd.encode('utf-8'), (known_l2c_ip, TARGET_PORT))
                print(f" [TX -> {known_l2c_ip}] 战术指令已下发: {cmd}")
            else:
                print(" [未就绪] 尚未收到前方 L2C 节点心跳，无法锁定目标 IP，请稍候...")
except KeyboardInterrupt:
    print("\n\n [CTRL+C] 接收到撤退指令，战术指挥中心正在安全关闭...")
    s.close()
    sys.exit(0)