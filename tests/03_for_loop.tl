-- tests/03_for_loop.tl
local function calc_ma(): integer
    local arr: {integer} = {10, 20, 30, 40, 50}
    local sum = 0
    
    -- Lua 经典的 for 循环（1到5）
    for i = 1, 5 do
        sum = sum + arr[i]
    end
    
    return sum
end

local ma = calc_ma()
print(ma)

-- EXPECT: 150
