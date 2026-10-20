-- ==============================================
-- 06_la_fpga.tl: 逻辑分析仪 (Tang Nano 9K 硅片端)
-- 编译目标: 纯 Verilog RTL (128-Byte Synchronous)
-- ==============================================

global function L2C_HDL_SEQ_la_sampler(clk: bit, rst_n: bit, rx_pins: uint8, read_clk: bit): uint8
    local state = HDL_Reg(0, 2)
    local w_ptr = HDL_Reg(0, 7)       -- 128 深度只需 7 位宽
    local r_ptr = HDL_Reg(0, 7)
    local last_read_clk = HDL_Reg(0, 1)
    local out_reg = HDL_Reg(0, 8)     -- [核心注入] 同步输出缓冲寄存器！
    
    local ram = HDL_BRAM(8, 128)

    last_read_clk = read_clk

    if state == 0 then
        w_ptr = 0                     -- 状态 0 时清零指针
        r_ptr = 0
        if (rx_pins & 1) == 0 then
            state = 1
        end
    elseif state == 1 then
        HDL_BRAM_Write(ram, w_ptr, rx_pins)
        if w_ptr == 127 then
            state = 2
            r_ptr = 0
        else
            w_ptr = w_ptr + 1
        end
    elseif state == 2 then
        -- [核心注入] 把 BRAM 的读取放在 if 控制流内，
        -- 编译器会自动生成 `out_reg <= ram[r_ptr];` 同步时序代码！
        out_reg = HDL_BRAM_Read(ram, r_ptr) 
        
        if read_clk == 1 and last_read_clk == 0 then
            r_ptr = r_ptr + 1
        end
    end
    
    -- 将同步寄存器连到输出端口，生成 assign out_0 = out_reg;
    return out_reg
end