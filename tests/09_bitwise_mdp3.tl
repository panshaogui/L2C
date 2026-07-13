-- tests/09_bitwise_mdp3.tl

local function parse_header(header: integer): integer
    -- 1. 位移操作 (Right Shift)：提取高 5 位
    local version = header >> 11
    
    -- 2. 位与操作 (Bitwise AND) + 十六进制字面量：提取低 11 位
    -- 0x07FF 的二进制是 0000 0111 1111 1111
    local template_id = header & 0x07FF
    
    -- 3. 按位取反 (Bitwise NOT) 测试
    local mask = ~0x07FF
    
    -- 我们仅仅为了断言验证，返回一个拼装的结果
    return version + template_id
end

-- 组装一个测试报文头：Version = 2 (左移11位), Template ID = 500 (位或)
local mock_header: integer = (2 << 11) | 500
local result = parse_header(mock_header)

print(result)
-- EXPECT: 502
