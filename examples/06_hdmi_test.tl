-- ==============================================
-- 06_hdmi_test.tl: L2C 图形光栅化引擎点火测试
-- 编译目标: 纯 Verilog RTL
-- 架构: L2C (图形着色) + Blackbox (官方 HDMI 物理层)
-- ==============================================

-- [核心注意] 为了让 L2C 把这些管脚当成 output，必须以 out_ 开头！
global function L2C_HDL_SEQ_hdmi_top(clk: bit, rst_n: bit, out_tmds_clk_p: bit, out_tmds_clk_n: bit, out_tmds_d_p: uint3, out_tmds_d_n: uint3, out_led: uint8): bit
    
    local clk_pixel = HDL_Wire(1)  
    local clk_5x = HDL_Wire(1)     
    local pll_lock = HDL_Wire(1)   
    
    local pix_x = HDL_Wire(10)     
    local pix_y = HDL_Wire(10)     
    local draw_en = HDL_Wire(1)    
    local hsync = HDL_Wire(1)      
    local vsync = HDL_Wire(1)      
    
    -- 安全复位阀
    local sys_rst_n = HDL_Wire(1)
    
    -- L2C 目前不支持直接写 wire a = b & c，所以我们用一个逻辑块
    if rst_n == 1 and pll_lock == 1 then
        sys_rst_n = 1
    else
        sys_rst_n = 0
    end

    -- 挂载官方黑盒
    HDL_Instance("gowin_rpll", "pll_inst", ".clkout(clk_5x), .clkoutd(clk_pixel), .clkin(clk), .lock(pll_lock)")
    HDL_Instance("vga_timing", "vga_inst", ".clk(clk_pixel), .rst_n(sys_rst_n), .hsync(hsync), .vsync(vsync), .draw_en(draw_en), .x(pix_x), .y(pix_y)")
    
    -- 注意这里的连线，必须匹配参数名
    HDL_Instance("dvi_tx", "hdmi_inst", ".clk_pixel(clk_pixel), .clk_5x(clk_5x), .rst_n(sys_rst_n), .r(red), .g(green), .b(blue), .hsync(hsync), .vsync(vsync), .draw_en(draw_en), .tmds_clk_p(out_tmds_clk_p), .tmds_clk_n(out_tmds_clk_n), .tmds_d_p(out_tmds_d_p), .tmds_d_n(out_tmds_d_n)")

    -- L2C GPU 着色器
    local red = HDL_Reg(0, 8)
    local green = HDL_Reg(0, 8)
    local blue = HDL_Reg(0, 8)

    if draw_en == 1 then
        -- 屏幕劈裂术：左半边 (0~319) 纯绿，右半边 (320~639) 纯蓝！(改了颜色以区分)
        if pix_x < 320 then
            red = 0
            green = 255
            blue = 0
        else
            red = 0
            green = 0
            blue = 255
        end
    else
        red = 0
        green = 0
        blue = 0
    end

    -- 为了简化，此处就不在 Teal 里生成那 6 颗 LED 复杂的探针分频逻辑了。
    -- 我们让 LED 输出一个静态状态：全亮
    out_led = 0 

    return 0
end