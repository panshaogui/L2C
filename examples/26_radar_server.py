import socket
import threading
import sys
import time

LISTEN_PORT = 8888       
TARGET_PORT = 8889       
active_fleet = {}  # 记录编队寿命

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(("0.0.0.0", LISTEN_PORT))

def redraw_prompt():
    sys.stdout.write('\r\x1b[2K> ')
    sys.stdout.flush()

def listen_loop():
    print(f" L2C-Mesh 多节点指挥中心已启动，监听 {LISTEN_PORT} 端口...")
    redraw_prompt()
    while True:
        try:
            data, addr = s.recvfrom(1024)
            ip = addr[0]
            now = time.time()
            
            is_new_node = ip not in active_fleet
            active_fleet[ip] = now
            
            msg = data.decode('utf-8', 'ignore')
            
            # 【防抖修复】如果是心跳包，只续命，绝对不碰屏幕，保护指挥官的打字光标！
            if msg.startswith("[HEARTBEAT]"):
                if is_new_node:
                    sys.stdout.write(f"\r\x1b[2K [入列] L2C 节点 {ip} 报到！\n")
                    redraw_prompt()
                continue
            
            # 收到真实敌情
            sys.stdout.write(f"\r\x1b[2K[情报 | {ip}] {msg}\n")
            redraw_prompt()
        except Exception:
            break

# 后台掉线检测雷达
def watchdog_loop():
    while True:
        time.sleep(5)
        now = time.time()
        # 超过 15 秒没收到心跳，判定阵亡
        offline_ips = [ip for ip, last_seen in list(active_fleet.items()) if now - last_seen > 15]
        
        for ip in offline_ips:
            del active_fleet[ip]
            sys.stdout.write(f"\r\x1b[2K [掉线] 失去与 L2C 节点 {ip} 的联系！\n")
            redraw_prompt()

threading.Thread(target=listen_loop, daemon=True).start()
threading.Thread(target=watchdog_loop, daemon=True).start()

try:
    while True:
        raw_cmd = input().strip()
        if not raw_cmd:
            redraw_prompt()
            continue
        
        if not active_fleet:
            print(" [未就绪] 战术编队空虚，无在线节点！")
            redraw_prompt()
            continue

        fleet_ips = list(active_fleet.keys())
        target_ip = None
        cmd = raw_cmd
        
        # 【路由解析】拦截 "@109 TX hello" 格式的精准定点指令
        if raw_cmd.startswith("@"):
            parts = raw_cmd.split(" ", 1)
            if len(parts) == 2:
                suffix = parts[0][1:] # 提取尾号，如 '109'
                # 在编队中搜索匹配该尾号的 IP
                for ip in fleet_ips:
                    if ip.endswith(suffix):
                        target_ip = ip
                        break
                
                if target_ip:
                    cmd = parts[1] # 剥离目标头，提取真实指令
                else:
                    print(f" [无效坐标] 战术编队中未找到尾号为 '{suffix}' 的节点！")
                    redraw_prompt()
                    continue

        cmd_upper = cmd.upper()
        
        # 【1】单体战术动作：狙击 (TX) 与 侦察 (SCAN)
        if cmd_upper.startswith("TX ") or cmd_upper.startswith("SCAN"):
            # 如果没指定目标，默认使用 1 号机
            shooter_ip = target_ip if target_ip else fleet_ips[0]
            s.sendto(cmd.encode('utf-8'), (shooter_ip, TARGET_PORT))
            role = " 狙击手" if cmd_upper.startswith("TX") else " 侦察兵"
            print(f" {role} | 已委派节点 ({shooter_ip}) 执行: {cmd}")
            
        # 【2】群体环境参数：调频 (FREQ) 与 扩频因子 (SF)
        elif cmd_upper.startswith("FREQ ") or cmd_upper.startswith("SF "):
            if target_ip:
                # 允许对单机强行配置
                s.sendto(cmd.encode('utf-8'), (target_ip, TARGET_PORT))
                print(f" [单机配置] 指令已下发至 {target_ip}: {cmd}")
            else:
                for ip in fleet_ips:
                    s.sendto(cmd.encode('utf-8'), (ip, TARGET_PORT))
                print(f" [全军同步] 环境参数已下发至 {len(fleet_ips)} 台节点: {cmd}")
                
        # 【3】其他广播指令
        else:
            if target_ip:
                s.sendto(cmd.encode('utf-8'), (target_ip, TARGET_PORT))
                print(f" [单点指令] 下发至 {target_ip}: {cmd}")
            else:
                for ip in fleet_ips:
                    s.sendto(cmd.encode('utf-8'), (ip, TARGET_PORT))
                print(f" [全军广播] 指令下发: {cmd}")
        
        redraw_prompt()

except KeyboardInterrupt:
    print("\n\n [CTRL+C] 接收到撤退指令，指挥中心安全关闭...")
    s.close()
    sys.exit(0)