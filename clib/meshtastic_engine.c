// =========================================================================
// [L2C Meshtastic 引擎] 纯正 ANSI C 标准实现 (全自动定长版)
// =========================================================================
#include "pb_decode.h"
#include "meshtastic/portnums.pb.h"
#include "meshtastic/mesh.pb.h"
#include "mbedtls/aes.h"
#include <string.h>
#include "pb_encode.h"

// [终极破壁] Meshtastic 官方 LongFast 隐藏的真实硬编码密钥！
// 当手机 App 显示 "AQ==" (0x01) 时，它实际上被底层映射为了这 16 个魔法字节！
static const uint8_t MESHTASTIC_DEFAULT_KEY[16] = {
    0xd4, 0xf1, 0xbb, 0x3a, 0x20, 0x29, 0x07, 0x59, 
    0xf0, 0xbc, 0xff, 0xab, 0xcf, 0x4e, 0x69, 0x01
};

// AES 原位解密 & Protobuf 0-GC 提取探针
// 返回 > 0: 成功解密，返回对应的 PortNum (1=Text, 3=Position, 4=NodeInfo)
// 返回 -1: 密码错误或格式错误
int l2c_mesh_decode_text(void* str_ptr, void* out_text) {
    uint8_t* p = (uint8_t*)str_ptr;
    int total_len = p[0];
    if (total_len <= 16) return 0; 

    // 1. 提取 PacketID 和 FromNode (构成 Nonce)
    uint32_t packet_id = *(uint32_t*)(p + 1 + 8);
    uint32_t from_node = *(uint32_t*)(p + 1 + 4);
    
    // Nonce 的 NodeID 必须放在偏移 8 的位置 (64-bit 对齐)
    uint8_t nonce_counter[16] = {0};
    memcpy(nonce_counter, &packet_id, 4);
    memcpy(nonce_counter + 8, &from_node, 4); 
    
    uint8_t* payload = p + 1 + 16;
    int payload_len = total_len - 16;

    // 2. AES-128-CTR 硬件加速原位粉碎
    mbedtls_aes_context aes;
    mbedtls_aes_init(&aes);
    mbedtls_aes_setkey_enc(&aes, MESHTASTIC_DEFAULT_KEY, 128);
    
    size_t nc_off = 0;
    uint8_t stream_block[16] = {0};
    mbedtls_aes_crypt_ctr(&aes, payload_len, &nc_off, nonce_counter, stream_block, payload, payload);
    mbedtls_aes_free(&aes);

    // 3. 【终极修复】空中的载荷是 meshtastic_Data，不是 MeshPacket！
    meshtastic_Data data_pkt = meshtastic_Data_init_zero;
    pb_istream_t stream = pb_istream_from_buffer(payload, payload_len);
    
    // 强制按 Data 结构体解码
    if (!pb_decode(&stream, meshtastic_Data_fields, &data_pkt)) {
        return -1; // 密文损坏或 AES 密钥错误
    }

    // 4. 如果是明文消息，直接拷出
    if (data_pkt.portnum == meshtastic_PortNum_TEXT_MESSAGE_APP) {
        uint8_t* text_buf = (uint8_t*)out_text;
        int text_len = data_pkt.payload.size;
        if (text_len > 250) text_len = 250;
        
        text_buf[0] = (uint8_t)text_len;
        memcpy(&text_buf[1], data_pkt.payload.bytes, text_len);
        text_buf[text_len + 1] = '\0';
    }

    // 返回真实的端口号 (PortNum)，让 Teal 层知道拦截到了什么包裹！
    return (int)data_pkt.portnum;
}
 
// =========================================================================
// [L2C Meshtastic 引擎] 终极伪装：全息注入封包器
// =========================================================================

// 将普通的字符串伪装成 Meshtastic 官方合法加密包裹
int l2c_mesh_encode_text_to_str(void* in_msg, int offset, void* out_pkt) {
    uint8_t* msg_ptr = (uint8_t*)in_msg;
    uint8_t* out_ptr = (uint8_t*)out_pkt;
    
    int msg_len = msg_ptr[0] - offset;
    if (msg_len <= 0) return 0;
    
    // 1. 伪造 16 字节物理明文头
    uint32_t to_node = 0xFFFFFFFF;   // 全局广播 (^all)
    uint32_t from_node = 0x4C324330; // 专属 ID: "L2C0" 的 Hex
    static uint32_t packet_id = 9999000;
    packet_id++; // 每次发包递增

    uint8_t* header = &out_ptr[1];
    memcpy(header, &to_node, 4);
    memcpy(header + 4, &from_node, 4);
    memcpy(header + 8, &packet_id, 4);
    header[12] = 0x03; // HopLimit = 3 (默认跳数)
    header[13] = 0x08; // Channel = 0x08 (LongFast Hash槽位)
    header[14] = 0x00;
    header[15] = 0x00;

    // 2. 0-GC 封包 Protobuf Data
    meshtastic_Data data_pkt = meshtastic_Data_init_zero;
    data_pkt.portnum = meshtastic_PortNum_TEXT_MESSAGE_APP;
    if (msg_len > 230) msg_len = 230; // 防止越界
    data_pkt.payload.size = msg_len;
    memcpy(data_pkt.payload.bytes, &msg_ptr[1 + offset], msg_len);

    uint8_t pb_buf[256];
    pb_ostream_t stream = pb_ostream_from_buffer(pb_buf, sizeof(pb_buf));
    if (!pb_encode(&stream, meshtastic_Data_fields, &data_pkt)) {
        return 0; // 封包失败
    }
    int pb_len = stream.bytes_written;

    // 3. 构建 Nonce 并执行 AES-CTR 加密
    uint8_t nonce_counter[16] = {0};
    memcpy(nonce_counter, &packet_id, 4);
    memcpy(nonce_counter + 8, &from_node, 4);

    mbedtls_aes_context aes;
    mbedtls_aes_init(&aes);
    mbedtls_aes_setkey_enc(&aes, MESHTASTIC_DEFAULT_KEY, 128);
    size_t nc_off = 0;
    uint8_t stream_block[16] = {0};
    
    // 直接将密文压入最终的发射缓冲区 (header 之后)
    uint8_t* payload_out = &out_ptr[1 + 16];
    mbedtls_aes_crypt_ctr(&aes, pb_len, &nc_off, nonce_counter, stream_block, pb_buf, payload_out);
    mbedtls_aes_free(&aes);

    // 4. 封装回 L2C 的 StackString 标准
    out_ptr[0] = 16 + pb_len; 
    return out_ptr[0]; // 返回最终的真实射频包长度
}
