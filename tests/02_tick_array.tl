-- tests/02_tick_array.tl
local function calc_sum(): integer
    -- 声明一个整型数组（滑动窗口）
    local arr: {integer} = {10, 20, 30}
    
    -- 取出数据求和 (注意：Lua/Nelua 都是 1-based 索引)
    return arr[1] + arr[2] + arr[3]
end

local sum: integer = calc_sum()
print(sum)

-- EXPECT: 60
