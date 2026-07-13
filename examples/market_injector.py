# market_injector.py
import zmq
import time
import json

def start_injector():
    context = zmq.Context()
    # 🎯 创建 PUB (发布者) 模式的 Socket
    sender = context.socket(zmq.PUB)
    sender.bind("tcp://127.0.0.1:5555")
    
    print("🚀 [行情注射器] 就绪，开始向 127.0.0.1:5555 轰炸高频 Tick 流...")
    
    tick_count = 0
    start_time = time.time()
    
    while True:
        tick_count += 1
        # 模拟高频做市商最关心的盘口 Ticker 数据
        payload = {
            "symbol": "BTC-USDT-SWAP",
            "bid": 68000.5 + (tick_count % 10),
            "ask": 68001.0 + (tick_count % 10),
            "vol": 12.5 + tick_count,
            "ts": int(time.time() * 1000)
        }
        
        # 极限全速扫射，不加任何 sleep！
        sender.send_string(json.dumps(payload))
        
        if tick_count % 100000 == 0:
            elapsed = time.time() - start_time
            print(f"🔥 已累计注射 {tick_count} 条 Tick | 当前吞吐率: {int(tick_count / elapsed)} msg/s")

if __name__ == "__main__":
    start_injector()
