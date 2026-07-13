// ==============================================================================
// Copyright (c) 2026 Panshaogui | MIT License
// L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
// ==============================================================================

// clib/simdjson_wrapper.cpp
#include <simdjson.h>

extern "C" {
    // 物理封装结构：把 Parser 和 DOM 树绑在一起防止被释放
    struct L2C_SimdJsonDoc {
        simdjson::dom::parser parser;
        simdjson::dom::element root;
    };

    void* simdjson_c_parse(const char* json_str, int len) {
        L2C_SimdJsonDoc* doc = new L2C_SimdJsonDoc();
        // simdjson 的硬核要求：解析时必须利用 CPU AVX 寄存器
        simdjson::error_code error = doc->parser.parse(json_str, len).get(doc->root);
        if (error) {
            delete doc;
            return nullptr;
        }
        return doc;
    }

    double simdjson_c_get_number(void* ptr, const char* key) {
        if (!ptr) return 0.0;
        L2C_SimdJsonDoc* doc = (L2C_SimdJsonDoc*)ptr;
        double val = 0.0;
        auto field = doc->root[key];
        if (field.error() == simdjson::SUCCESS) {
            // 🔥 [严谨对齐]：接住并处理 simdjson 强制要求返回的 error_code，消灭 warning
            auto err = field.get_double().get(val);
            if (err) { val = 0.0; }
        }
        return val;
    }

    void simdjson_c_free(void* ptr) {
        if (ptr) delete (L2C_SimdJsonDoc*)ptr;
    }
}
