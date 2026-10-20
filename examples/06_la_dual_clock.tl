-- ==============================================
-- 06_la_dual_clock.tl: L2C 双时钟域逻辑分析仪
-- 编译目标: 纯 Verilog RTL
-- 架构: 多时钟域分离 (AST 引擎) + 声明与黑盒 (老引擎)
-- ==============================================

-- [核心魔法] 去掉了 SEQ_ 前缀！关闭老引擎的全局时钟块！
global function L2C_HDL_la_top(
    clk: bit, rst_n: bit, rx_pins: uint8,
    out_tmds_clk_p: bit, out_tmds_clk_n: bit,
    out_tmds_d_p: uint3, out_tmds_d_n: uint3,
    out_led: uint8
): bit

    -- 1. 物理线与组合逻辑 (自动被老引擎推断为 wire 和 assign)
    local clk_pixel = HDL_Wire(1)
    local clk_126m = HDL_Wire(1)
    local pll_lock = HDL_Wire(1)
    local sys_rst_n = rst_n & pll_lock

    local pix_x = HDL_Wire(10)
    local pix_y = HDL_Wire(10)
    local draw_en = HDL_Wire(1)
    local hsync = HDL_Wire(1)
    local vsync = HDL_Wire(1)

    -- 2. 挂载官方黑盒 IP
    HDL_Instance("gowin_rpll", "pll_inst", ".clkout(clk_126m), .clkoutd(clk_pixel), .clkin(clk), .lock(pll_lock)")
    HDL_Instance("vga_timing", "vga_inst", ".clk(clk_pixel), .rst_n(sys_rst_n), .hsync(hsync), .vsync(vsync), .draw_en(draw_en), .x(pix_x), .y(pix_y)")
    HDL_Instance("dvi_tx", "hdmi_inst", ".clk_pixel(clk_pixel), .clk_5x(clk_126m), .rst_n(sys_rst_n), .r(out_red), .g(out_green), .b(out_blue), .hsync(hsync), .vsync(vsync), .draw_en(draw_en), .tmds_clk_p(out_tmds_clk_p), .tmds_clk_n(out_tmds_clk_n), .tmds_d_p(out_tmds_d_p), .tmds_d_n(out_tmds_d_n)")

    -- 3. 内存与寄存器声明 (老引擎自动生成 reg，并且不产生冲突的 reset)
    local ram = HDL_BRAM(8, 1024)

    local state = HDL_Reg(0, 2)
    local waddr = HDL_Reg(0, 10)

    local out_red = HDL_Reg(0, 8)
    local out_green = HDL_Reg(0, 8)
    local out_blue = HDL_Reg(0, 8)

    local wave_data = HDL_Reg(0, 8)
    local wave_data_prev = HDL_Reg(0, 8)
    local x_d = HDL_Reg(0, 10)
    local y_d = HDL_Reg(0, 10)
    local draw_en_d = HDL_Reg(0, 1)

    -- ==============================================================
    -- [第一时钟域] 狂暴采样区：126MHz (由 AST 引擎处理)
    -- ==============================================================
    if HDL_Clock_Domain(clk_126m, sys_rst_n) then
        if sys_rst_n == 0 then
            state = 0
            waddr = 0
        else
            if state == 0 then
                waddr = 0
                if rx_pins ~= 255 then
                    state = 1
                end
            elseif state == 1 then
                HDL_BRAM_Write(ram, waddr, rx_pins)
                waddr = waddr + 1
                if waddr == 639 then
                    state = 2
                end
            elseif state == 2 then
                -- 抓满后保持死循环，等待人工按硬件 rst_n 按键重置
            end
        end
    end

    -- ==============================================================
    -- [第二时钟域] 视觉渲染区：25.2MHz (由 AST 引擎处理)
    -- ==============================================================
    if HDL_Clock_Domain(clk_pixel, sys_rst_n) then
        if sys_rst_n == 0 then
            x_d = 0
            y_d = 0
            draw_en_d = 0
        else
            -- 内存读取流水线对齐 (延迟一拍对齐坐标)
            wave_data = HDL_BRAM_Read(ram, pix_x)
            x_d = pix_x
            y_d = pix_y
            draw_en_d = draw_en
            if draw_en == 1 then
                wave_data_prev = wave_data
            end

            -- 极简着色器：渲染 CH0 波形 (提取第 0 位电平)
            if draw_en_d == 1 then
                -- 注意这里的位运算和数字比较，AST 引擎将完美翻译为 Verilog
                if (wave_data & 1) == 1 then
                    if y_d > 200 and y_d < 220 then
                        out_green = 255
                    else
                        out_green = 0
                    end
                else
                    if y_d > 260 and y_d < 280 then
                        out_green = 255
                    else
                        out_green = 0
                    end
                end
                
                -- 画一根极其微弱的暗线作为背景基准
                if out_green == 0 then
                    out_red = 20
                    out_blue = 20
                else
                    out_red = 0
                    out_blue = 0
                end
            else
                out_red = 0
                out_green = 0
                out_blue = 0
            end
        end
    end

    -- [老引擎组合逻辑] 输出管脚直接赋固定值 (全灭 = 高电平)
    out_led = 255
    return 0
end