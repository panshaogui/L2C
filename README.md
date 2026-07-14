# 🚀 L2C Compiler: The 0-GC Native Engine for HFT & IoT

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![0-GC](https://img.shields.io/badge/Memory-0--GC-red.svg)](#)
[![HFT](https://img.shields.io/badge/Domain-High--Frequency--Trading-blue.svg)](#)
[![IoT](https://img.shields.io/badge/Domain-Embedded--IoT-green.svg)](#)

**Transpile Typed Lua directly into 0-GC Native C.**

L2C is a highly opinionated, zero-garbage-collection, ahead-of-time (AOT) transpiler pipeline. It combines the elegant syntax and static typing of [Teal](https://github.com/teal-language/tl) with the bare-metal C memory control of [Nelua](https://github.com/edubart/nelua-lang).

If you are tired of fighting C++ template errors, or frustrated by Python/Go GC pauses (Jitters) in microsecond-critical environments, L2C is your ultimate weapon.

---

## ⚡ The "L2C Strict Subset" Philosophy (Read Before Use)

**⚠️ WARNING: L2C IS NOT A GENERAL-PURPOSE LUA COMPILER.**

L2C physically strips out Garbage Collection. We force "Mechanical Sympathy" upon the developer. 
If you want full Lua semantics with a VM, use LuaJIT. If you want to write strategy logic in script syntax but compile it to a **~35KB standalone executable** (or MCU firmware) that runs at the speed of raw ANSI C, you are in the right place.

### ✅ What we EXCLUSIVELY support:
*   **Physical Stack Memory**: `L2C_Buffer(size)`, `L2C_NumberArray(size)` for O(1) allocation.
*   **Tick-Level Arena Allocator**: 10MB pre-allocated pools with `L2C_Tick_Reset()` for O(1) instant memory recycling.
*   **Zero-Copy Cast**: `Type._cast(ptr)` translates byte buffers directly into struct pointers without deserialization.
*   **C-FFI Unity Build**: Direct injection of C headers and static libraries via `-- @l2c_import` and `@l2c_link`.
*   **C Callback Pointers**: `L2C_FuncPtr(func)` safely casts Lua functions to `void*` for async OS callbacks.

### ❌ What we STRICTLY FORBID:
*   Dynamic string concatenation (`"a" .. "b"`).
*   Untyped dynamic tables (Dictionaries).
*   Closures (Upvalues) and Coroutines.
*   Anything that triggers implicit heap allocation.

---

## 🛠️ Ecosystem & Standard Library (L2C-STD)

L2C comes with an expanding array of 0-GC FFI wrappers for the world's most powerful C/C++ libraries, featuring the **"Invisible Debt Registry"** to automatically handle linker flags (`-lc++`, `-lsodium`, etc.):

*   🌐 **`std/zmq.tl`**: Microsecond-latency network gateways (ZeroMQ).
*   🚀 **`std/nanomsg.tl`**: Nanosecond-latency IPC shared memory bus.
*   💾 **`std/sqlite.tl`**: 0-allocation SQL transaction logging.
*   ⚡ **`std/simdjson.tl`**: AVX-512/SSE4.2 accelerated JSON parsing via C++ wrappers.
*   ⏱️ **`std/uv.tl`**: C10K async event loops (libuv).
*   🔌 **`std/pico.tl` & `std/freertos.tl`**: Bare-metal RTOS task scheduling for RP2040 (Raspberry Pi Pico) and ESP32.

---

## 🚀 Quick Start

### 1. Build the Compiler (Self-Contained Binary)
Using our inception-style meta-compiler, generate a standalone `l2c_bin` that embeds the Lua VM and AST parser:
```bash
lua build_native_l2c.lua
# Yields a ~700KB standalone 'l2c_bin' executable
```

---

### 2. Write your HFT Strategy (`examples/11_hft_sniper.tl`)
```lua
-- examples/11_hft_sniper.tl
-- 📦 物理引入 L2C 标准库 (zmq 内部已经声明了 L2C_Buffer 和 L2C_Ref)
-- @l2c_import: std/zmq.tl

-- 1. 定义交易所推送的二进制内存对齐结构
local type TickPacket = record
    symbol_id: integer
    price: integer
    qty: integer
    -- 🔥 开启零拷贝强转特权
    _cast: function(any): TickPacket
end

-- 2. 策略状态：在 C 栈上开辟一块 5 周期的极速滑动窗口，0 GC！
local ma_window: {integer} = {0, 0, 0, 0, 0}
local window_idx = 1
local is_filled = false

-- 3. 核心策略：微型均线突破刺客
local function on_tick_received(pkt: TickPacket)
    -- 更新滑动窗口 (完美映射底层 0-based C 数组)
    ma_window[window_idx] = pkt.price
    window_idx = window_idx + 1
    if window_idx > 5 then
        window_idx = 1
        is_filled = true
    end
    
    if is_filled == false then return end
    
    -- 极限 For 循环计算均线
    local sum = 0
    for i = 1, 5 do
        sum = sum + ma_window[i]
    end
    -- ⚡ 使用整数除法 // ，压榨 CPU 时钟周期
    local ma_price = sum // 5
    
    -- 核心狙击逻辑：价格瞬间突破均线，且带量！
    if pkt.price > ma_price then
        if pkt.qty > 100 then
            print("🔫 [狙击开火] 捕捉到放量突破！Symbol:", pkt.symbol_id, "Price:", pkt.price, "MA:", ma_price)
        end
    end
end

-- ==========================================
-- 🚀 物理网关主程序
-- ==========================================
print("⚡ L2C HFT Sniper 引擎启动，挂载 ZMQ 网卡...")
local ctx = C_ZMQ.zmq_ctx_new()
local subscriber = C_ZMQ.zmq_socket(ctx, 2) -- ZMQ_SUB
C_ZMQ.zmq_connect(subscriber, "tcp://127.0.0.1:5555")

local msg_buf = L2C_Buffer(24)

print("📡 雷达已锁定，等待二进制 Tick 数据轰炸...")

while true do
    local bytes = C_ZMQ.zmq_recv(subscriber, L2C_Ref(msg_buf), 24, 0)
    if bytes > 0 then
        -- 🔥 零拷贝降维打击：字节流原地变身为 TickPacket 结构体！
        local tick: TickPacket = TickPacket._cast(L2C_Ref(msg_buf))
        on_tick_received(tick)
    end
end
```

---

### 3. Compile to Host OS / Cloud Servers
> **Note for Windows Users**: Native Windows build is intentionally unsupported to maintain extreme 0-GC POSIX performance. Please use **WSL2 (Ubuntu)**.

```bash
# Host Machine (macOS/Linux Native)
./l2c_bin examples/11_hft_sniper.tl -o hft_bot

# Alpine/Musl Linux (Fully Statically Linked ELF)
./build_musl.sh examples/11_hft_sniper.tl -o linux_bot
```

---

### 4. Cross-Compile to Edge IoT (Pico / ESP32 Firmware)
L2C uses Docker-based "Forges" to completely eliminate the pain of configuring MCU toolchains (ARM GCC, Pico SDK, ESP-IDF, FreeRTOS).

```bash
# Step 1: Emit raw, 0-GC C-code from your Teal logic
./l2c_bin examples/19_pico_blinky.tl -o main --target=pico --emit-c

# Step 2: Spin up the cross-compilation Forge in the background
docker compose up -d l2c-pico-forge

# Step 3: Dive into the container and melt the silicon
docker compose exec l2c-pico-forge /bin/sh

/workspace # mkdir build && cd build
/workspace/build # cmake ..
/workspace/build # make -j4

# Output: firmware.uf2 is generated and ready to flash!
```

---

## 🤝 Contributing
This is a community-driven subset. Found a missing AST node that fits our 0-GC philosophy? PRs are highly welcome. Just add your `gen_xxx` in `codegen/` and provide a test case in `tests/unit/`.

**For any feature request requiring a Garbage Collector: Won't fix. Closed.**

> *Copyright (c) 2026 Panshaogui | MIT License*