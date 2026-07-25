-- tests/fail_02_closure.tl
-- EXPECT_FAIL: E002

local function do_something(cb: function())
    cb()
end

print("试图用闭包逃过检查...")

do_something(function()
    print("hello L2C")
end)