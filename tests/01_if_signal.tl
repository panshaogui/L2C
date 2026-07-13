-- test.tl
local type Order = record
    price: integer
    qty: integer
end

local function check_signal(o: Order): integer
    if o.price > 100 then
        return 1  -- 做多
    else
        return 0  -- 观望
    end
end

local my_order: Order = { price = 105, qty = 10 }
local signal: integer = check_signal(my_order)
print(signal)
-- EXPECT: 1
