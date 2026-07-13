-- tests/08_while_loop.tl
-- 这是一个纯逻辑控制流测试，不依赖任何外部变量状态
-- EXPECT:count=5inner=3

local count = 0
-- 第一个循环：测试基础 while 结构
while count < 5 do
    count = count + 1
end
print("count=5")

-- 第二个循环：测试 return 对死循环的强力阻断
local i = 0
while true do
    i = i + 1
    if i == 3 then
        print("inner=3")
        return -- 🎯 关键点：这是编译器的控制流转译核心，必须能物理打断循环
    end
end
