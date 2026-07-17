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
docker compose up -d  l2c-compiler

docker compose exec l2c-compiler /bin/sh

lua build_native_l2c.lua

# Yields a ~700KB standalone 'l2c_bin' executable
```

---

### 2. Write your HFT Strategy (`examples/07_strategy.tl`)
```lua
-- @l2c_import: std/zmq.tl
-- @l2c_import: std/cjson.tl

-- Initialize ZMQ Subscriber
local ctx = C_ZMQ.zmq_ctx_new()
local subscriber = C_ZMQ.zmq_socket(ctx, 2)
C_ZMQ.zmq_connect(subscriber, "tcp://127.0.0.1:5555")

local function on_tick()
    local buf = L2C_Buffer(1024)
    local bytes = C_ZMQ.zmq_recv(subscriber, L2C_Ref(buf), 1024, 0)
    
    if bytes > 0 then
        -- 0-GC DOM parsing on C-Heap
        local root = cjson_parse(L2C_Cast(L2C_Ref(buf), "cstring"))
        local price = cjson_get_number(root, "price")
        print("Market Tick Price: ", price)
        cjson_free(root)
    end
    
    -- O(1) Memory Pool Reset to prevent OOM
    L2C_Tick_Reset()
end
```

---

### 3. Compile to Host OS / Cloud Servers
> **Note for Windows Users**: Native Windows build is intentionally unsupported to maintain extreme 0-GC POSIX performance. Please use **WSL2 (Ubuntu)**.

```bash
# Host Machine (macOS/Linux Native)
./l2c_bin examples/07_strategy.tl -o hft_bot

# Alpine/Musl Linux (Fully Statically Linked ELF)
./build_musl.sh examples/07_strategy.tl -o linux_bot
```

---

### 4. Cross-Compile to Edge IoT (Pico / ESP32 Firmware)
L2C uses Docker-based "Forges" to completely eliminate the pain of configuring MCU toolchains (ARM GCC, Pico SDK, ESP-IDF, FreeRTOS).

```bash
# Step 1: Emit raw, 0-GC C-code from your Teal logic
docker compose up -d  l2c-compiler

docker compose exec l2c-compiler /bin/sh

./l2c_bin examples/20_pico_sniper.tl -o main --target=pico --emit-c

# Step 2: Spin up the cross-compilation Forge in the background
docker compose up -d l2c-pico-forge

# Step 3: Dive into the container and melt the silicon
docker compose exec l2c-pico-forge /bin/sh

mkdir build && cd build
cmake ..
make -j4

# Output: firmware.uf2 is generated and ready to flash!
```

---

## 🤝 Contributing
This is a community-driven subset. Found a missing AST node that fits our 0-GC philosophy? PRs are highly welcome. Just add your `gen_xxx` in `codegen/` and provide a test case in `tests/unit/`.

**For any feature request requiring a Garbage Collector: Won't fix. Closed.**

> *Copyright (c) 2026 Panshaogui | MIT License*