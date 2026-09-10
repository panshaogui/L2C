# =========================================================================
# L2C 兵工厂 - ESP-IDF 精准挂载脚本 (0-GC 极简版)
# =========================================================================

# 注册组件：扔掉所有无用的 Protobuf，只带上破开通信外壳的两把钥匙！
idf_component_register(
    SRCS 
        "pb_decode.c"
        "pb_encode.c" 
        "pb_common.c" 
        "meshtastic_engine.c" 
        "mesh_proto/meshtastic/mesh.pb.c"       # [核心] 报文外壳结构体
        "mesh_proto/meshtastic/portnums.pb.c"   # [核心] 端口号枚举定义
    INCLUDE_DIRS 
        "." 
        "mesh_proto"
    REQUIRES 
        mbedtls
)
