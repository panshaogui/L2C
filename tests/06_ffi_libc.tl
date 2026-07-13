-- tests/06_ffi_libc.tl
-- @l2c_include: stdio.h
-- @l2c_include: unistd.h

local type C = record
    -- 声明原生 C 库函数
    puts: function(string): integer
    sleep: function(integer): integer
end

-- 穿越开始
-- C.puts("Hello from C FFI, running on bare-metal M4!")
-- C.sleep(1)
C.puts("Wake up!")

-- EXPECT: Wake up!
