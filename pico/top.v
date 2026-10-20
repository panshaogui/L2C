// ==============================================
// 手工物理基线: HDMI 探针诊断版
// ==============================================
module hdmi_top(
    input wire clk,
    input wire rst_n,
    output wire tmds_clk_p,       // 改名直接对应原语
    output wire tmds_clk_n,
    output wire [2:0] tmds_d_p,
    output wire [2:0] tmds_d_n,
    output wire [5:0] led         // 你的六维物理探针舱
);

    wire clk_pixel, clk_5x, pll_lock;
    
    // 1. PLL 锁相环
    gowin_rpll pll_inst (
        .clkout(clk_5x), 
        .clkoutd(clk_pixel), 
        .clkin(clk), 
        .lock(pll_lock)
    );

    wire [9:0] pix_x, pix_y;
    wire draw_en, hsync, vsync;
    
    wire sys_rst_n = rst_n & pll_lock;

    // 2. VGA 时序发生器
    vga_timing vga_inst (
        .clk(clk_pixel), 
        .rst_n(sys_rst_n), 
        .hsync(hsync), 
        .vsync(vsync), 
        .draw_en(draw_en), 
        .x(pix_x), 
        .y(pix_y)
    );

    reg [7:0] red, green, blue;

    // 3. 图形光栅化
    always @(posedge clk_pixel) begin
        if (draw_en) begin
            if (pix_x < 320) begin
                red <= 255; green <= 0; blue <= 0;
            end else begin
                red <= 0; green <= 0; blue <= 255;
            end
        end else begin
            red <= 0; green <= 0; blue <= 0;
        end
    end

    // 4. HDMI 发射器例化（确保端口名完全对齐）
    dvi_tx hdmi_inst (
        .clk_pixel(clk_pixel), 
        .clk_5x(clk_5x), 
        .rst_n(sys_rst_n), 
        .r(red), .g(green), .b(blue), 
        .hsync(hsync), .vsync(vsync), .draw_en(draw_en), 
        .tmds_clk_p(tmds_clk_p),   // 对应顶层的 tmds_clk_p（绝对不要加 out_ 前缀）
        .tmds_clk_n(tmds_clk_n), 
        .tmds_d_p(tmds_d_p),       // 对应顶层的 tmds_d_p
        .tmds_d_n(tmds_d_n)
    );

    // ==========================================
    // 5. [核心注入] 六维物理探针诊断舱 (Active Low: 0=亮)
    // ==========================================
    
    // LED 0: 27MHz 系统时钟心跳 (分频闪烁)
    reg [24:0] cnt_sys;
    always @(posedge clk) cnt_sys <= cnt_sys + 1;
    assign led[0] = ~cnt_sys[24]; 

    // LED 1: PLL 锁定状态 (常亮 = 正常)
    assign led[1] = ~pll_lock;

    // LED 2: 25MHz 像素时钟心跳 (分频闪烁)
    reg [24:0] cnt_pix;
    always @(posedge clk_pixel) cnt_pix <= cnt_pix + 1;
    assign led[2] = ~cnt_pix[24];

    // LED 3: VSYNC 场同步心跳 (60Hz -> 分频闪烁)
    reg [5:0] cnt_vsync;
    always @(posedge vsync) cnt_vsync <= cnt_vsync + 1;
    assign led[3] = ~cnt_vsync[5];

    // LED 4: 系统复位解除状态 (常亮 = 正常)
    assign led[4] = ~sys_rst_n;

    // LED 5: 显示使能区指示 (高速闪烁，肉眼看是常亮偏暗 = 正在向屏幕吐像素)
    assign led[5] = ~draw_en;

endmodule