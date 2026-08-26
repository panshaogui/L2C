-- tests/fail_08_table_mutation.tl
-- EXPECT_FAIL: invalid key 'z'

local type Point = record
    x: integer
    y: integer
end

local p: Point = { x = 10, y = 20 }

print("试图给静态 Struct 强行写入未定义的动态属性...")

-- 严禁动态扩展内存结构。Teal 会判定 'z' 为非法 key。
p.z = 30