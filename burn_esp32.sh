# =======================================================================
# 锻造 Web Serial API 一键烧录舱 (动态嗅探物理偏移量)
# =======================================================================
echo " 正在读取 ESP-IDF 官方物理偏移量，动态生成 Web 烧录清单..."

# 核心魔法：使用 Python 瞬间解析 flasher_args.json，提取真实偏移量并生成 manifest.json！
python3 -c "
import json
import os

# 读取 ESP-IDF 生成的官方烧录参数
with open('esp32/build/flasher_args.json') as f:
    data = json.load(f)

# 动态提取芯片型号 (如 ESP32, ESP32-S3)
chip_family = data.get('extra_esptool_args', {}).get('chip', 'ESP32').upper()

# 动态提取每一段的偏移量 (16进制转10进制) 和对应的 bin 文件
parts = []
for hex_offset, filename in data['flash_files'].items():
    parts.append({
        'path': filename,
        'offset': int(hex_offset, 16)
    })

# 组装 Web Flasher 要求的 Manifest 格式
manifest = {
    'name': 'L2C Zero-GC Firmware',
    'version': '1.0.0',
    'builds': [
        {
            'chipFamily': chip_family,
            'parts': parts
        }
    ]
}

# 写入文件
with open('esp32/build/manifest.json', 'w') as f:
    json.dump(manifest, f, indent=2)
"

echo " 动态清单 manifest.json 生成完毕！"

# 生成赛博极客风的 Web 烧录界面
cat << 'EOF' > esp32/build/index.html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>L2C Web Flasher</title>
  <script type="module" src="https://unpkg.com/esp-web-tools@10.0.1/dist/web/install-button.js?module"></script>
  <style>
    body { background-color: #0d1117; color: #00ffff; font-family: 'Courier New', Courier, monospace; text-align: center; padding-top: 100px; }
    h1 { font-size: 3em; text-shadow: 0 0 10px #00ffff; }
    p { font-size: 1.2em; color: #8b949e; }
    .flasher-box { margin-top: 50px; padding: 30px; border: 1px dashed #00ffff; display: inline-block; border-radius: 10px; background: #161b22; }
  </style>
</head>
<body>
  <h1> L2C Web Flasher</h1>
  <p>纯净的物理硅片通道。免环境配置，直击底层。</p>
  <div class="flasher-box">
    <esp-web-install-button manifest="manifest.json"></esp-web-install-button>
  </div>
  <p style="margin-top: 50px; font-size: 0.9em; color: #ff4444;"> 请务必使用 Chrome / Edge 浏览器，并使用数据线连接开发板。</p>
</body>
</html>
EOF

echo "============================================================"
echo " 烧录舱就绪！在您的终端执行以下命令开启本地 Web 服务器："
echo " python3 -m http.server --directory esp32/build"
echo ""
echo " 然后在宿主机使用 Chrome 浏览器打开: http://localhost:8000"
echo "============================================================"
