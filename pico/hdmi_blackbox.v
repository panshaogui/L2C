// ==============================================================================
// L2C Blackbox IP: HDMI / DVI 物理输出 (高云官方 IDE 专享完美版)
// ==============================================================================

// 1. Gowin 锁相环 (官方正统架构：PLL输出126M + CLKDIV分频得到25.2M)
module gowin_rpll (output clkout, output clkoutd, input clkin, output lock);
    wire clk_5x;
    
    // 只输出 126MHz 的高速时钟 (去掉了不合法的 DYN_SDIV_SEL)
    rPLL #(
        .FCLKIN("27"), 
        .IDIV_SEL(2),       // 27 / 3 = 9 MHz
        .FBDIV_SEL(13),     // 9 * 14 = 126 MHz
        .ODIV_SEL(4)        // VCO = 126 * 4 = 504 MHz
    ) pll_inst (
        .CLKOUT(clk_5x), .CLKOUTD(), .CLKIN(clkin), .LOCK(lock),
        .RESET(1'b0), .RESET_P(1'b0), .CLKFB(1'b0), .FBDSEL(6'b0), .IDSEL(6'b0),
        .ODSEL(6'b0), .PSDA(4'b0), .DUTYDA(4'b0), .FDLY(4'b0)
    );

    assign clkout = clk_5x;

    // 官方 IDE 的最爱：使用专用硬件分频网络 (126MHz / 5 = 25.2MHz)
    CLKDIV #(.DIV_MODE("5")) clk_div_inst (
        .CLKOUT(clkoutd), .HCLKIN(clk_5x), .RESETN(lock)
    );
endmodule

// 2. VGA 时序发生器
module vga_timing(
    input clk, input rst_n, output hsync, output vsync, output draw_en, output reg [9:0] x, output reg [9:0] y
);
    reg [9:0] h_count = 0; reg [9:0] v_count = 0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin h_count <= 0; v_count <= 0; end 
        else begin
            if (h_count == 800 - 1) begin
                h_count <= 0; v_count <= (v_count == 525 - 1) ? 0 : v_count + 1;
            end else h_count <= h_count + 1;
        end
    end
    assign hsync = ~(h_count >= 640 + 16 && h_count < 640 + 16 + 96);
    assign vsync = ~(v_count >= 480 + 10 && v_count < 480 + 10 + 2);
    assign draw_en = (h_count < 640) && (v_count < 480);
    always @(posedge clk) begin
        x <= (h_count < 640) ? h_count : 10'd0;
        y <= (v_count < 480) ? v_count : 10'd0;
    end
endmodule

// 3. TMDS 编码器 (直流平衡安全版)
module tmds_encoder(input clk, input [7:0] vd, input [1:0] cd, input vde, output reg [9:0] tmds);
    wire [3:0] n1d = vd[0] + vd[1] + vd[2] + vd[3] + vd[4] + vd[5] + vd[6] + vd[7];
    wire xno = (n1d > 4'd4) || (n1d == 4'd4 && vd[0] == 1'b0);
    wire [8:0] q_m;
    assign q_m[0] = vd[0];
    assign q_m[1] = q_m[0] ^ vd[1] ^ xno; assign q_m[2] = q_m[1] ^ vd[2] ^ xno;
    assign q_m[3] = q_m[2] ^ vd[3] ^ xno; assign q_m[4] = q_m[3] ^ vd[4] ^ xno;
    assign q_m[5] = q_m[4] ^ vd[5] ^ xno; assign q_m[6] = q_m[5] ^ vd[6] ^ xno;
    assign q_m[7] = q_m[6] ^ vd[7] ^ xno; assign q_m[8] = ~xno;
    reg [4:0] cnt = 0; 
    wire [3:0] n1q_m = q_m[0] + q_m[1] + q_m[2] + q_m[3] + q_m[4] + q_m[5] + q_m[6] + q_m[7];
    wire [3:0] n0q_m = 4'd8 - n1q_m;
    always @(posedge clk) begin
        if (!vde) begin
            cnt <= 5'd0;
            tmds <= (cd == 2'b00) ? 10'b1101010100 : (cd == 2'b01) ? 10'b0010101011 : (cd == 2'b10) ? 10'b0101010100 : 10'b1010101011;
        end else begin
            if (cnt == 5'd0 || n1q_m == n0q_m) begin
                tmds[9] <= ~q_m[8]; tmds[8] <= q_m[8]; tmds[7:0] <= q_m[8] ? q_m[7:0] : ~q_m[7:0];
                cnt <= cnt + (q_m[8] ? (n1q_m - n0q_m) : (n0q_m - n1q_m));
            end else begin
                if ((!cnt[4] && cnt != 0 && n1q_m > n0q_m) || (cnt[4] && n0q_m > n1q_m)) begin
                    tmds[9] <= 1'b1; tmds[8] <= q_m[8]; tmds[7:0] <= ~q_m[7:0];
                    cnt <= cnt + {3'b0, q_m[8], 1'b0} + n0q_m - n1q_m;
                end else begin
                    tmds[9] <= 1'b0; tmds[8] <= q_m[8]; tmds[7:0] <= q_m[7:0];
                    cnt <= cnt - {3'b0, ~q_m[8], 1'b0} + n1q_m - n0q_m;
                end
            end
        end
    end
endmodule

// 4. DVI_TX (官方 IDE 会完美布线 TLVDS 和 OSER10)
module dvi_tx(
    input clk_pixel, input clk_5x, input rst_n,
    input [7:0] r, input [7:0] g, input [7:0] b,
    input hsync, input vsync, input draw_en,
    output tmds_clk_p, output tmds_clk_n,
    output [2:0] tmds_d_p, output [2:0] tmds_d_n
);
    wire [9:0] tmds_r, tmds_g, tmds_b;
    tmds_encoder enc_r(.clk(clk_pixel), .vd(r), .cd(2'b00), .vde(draw_en), .tmds(tmds_r));
    tmds_encoder enc_g(.clk(clk_pixel), .vd(g), .cd(2'b00), .vde(draw_en), .tmds(tmds_g));
    tmds_encoder enc_b(.clk(clk_pixel), .vd(b), .cd({vsync, hsync}), .vde(draw_en), .tmds(tmds_b));
    wire [3:0] tmds_data; 
    
    OSER10 oser_b(.Q(tmds_data[0]), .D0(tmds_b[0]), .D1(tmds_b[1]), .D2(tmds_b[2]), .D3(tmds_b[3]), .D4(tmds_b[4]), .D5(tmds_b[5]), .D6(tmds_b[6]), .D7(tmds_b[7]), .D8(tmds_b[8]), .D9(tmds_b[9]), .PCLK(clk_pixel), .FCLK(clk_5x), .RESET(~rst_n));
    OSER10 oser_g(.Q(tmds_data[1]), .D0(tmds_g[0]), .D1(tmds_g[1]), .D2(tmds_g[2]), .D3(tmds_g[3]), .D4(tmds_g[4]), .D5(tmds_g[5]), .D6(tmds_g[6]), .D7(tmds_g[7]), .D8(tmds_g[8]), .D9(tmds_g[9]), .PCLK(clk_pixel), .FCLK(clk_5x), .RESET(~rst_n));
    OSER10 oser_r(.Q(tmds_data[2]), .D0(tmds_r[0]), .D1(tmds_r[1]), .D2(tmds_r[2]), .D3(tmds_r[3]), .D4(tmds_r[4]), .D5(tmds_r[5]), .D6(tmds_r[6]), .D7(tmds_r[7]), .D8(tmds_r[8]), .D9(tmds_r[9]), .PCLK(clk_pixel), .FCLK(clk_5x), .RESET(~rst_n));
    OSER10 oser_c(.Q(tmds_data[3]), .D0(1'b1), .D1(1'b1), .D2(1'b1), .D3(1'b1), .D4(1'b1), .D5(1'b0), .D6(1'b0), .D7(1'b0), .D8(1'b0), .D9(1'b0), .PCLK(clk_pixel), .FCLK(clk_5x), .RESET(~rst_n));

    ELVDS_OBUF obuf_b(.O(tmds_d_p[0]), .OB(tmds_d_n[0]), .I(tmds_data[0]));
    ELVDS_OBUF obuf_g(.O(tmds_d_p[1]), .OB(tmds_d_n[1]), .I(tmds_data[1]));
    ELVDS_OBUF obuf_r(.O(tmds_d_p[2]), .OB(tmds_d_n[2]), .I(tmds_data[2]));
    ELVDS_OBUF obuf_c(.O(tmds_clk_p),  .OB(tmds_clk_n),  .I(tmds_data[3]));
endmodule