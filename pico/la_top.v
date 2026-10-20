// ==============================================================================
// 黄金物理基线: 126MHz HDMI 逻辑分析仪 (Tang Nano 9K + Gowin IDE)
// ==============================================================================

module la_top(
    input wire clk,             // 27MHz 系统晶振
    input wire rst_n,           // 物理复位按键
    input wire [7:0] rx_pins,   // 8 通道逻辑分析仪探针
    output wire tmds_clk_p, output wire tmds_clk_n,
    output wire [2:0] tmds_d_p, output wire [2:0] tmds_d_n,
    output wire [5:0] led       // 探针状态灯
);

    // ==========================================
    // 1. 时钟心脏：双核引擎心跳
    // ==========================================
    wire clk_pixel; // 25.2MHz 慢时钟 (用于屏幕刷新与显存读取)
    wire clk_126m;  // 126.0MHz 快时钟 (用于 HDMI 物理层与探针超高速采样)
    wire pll_lock;
    wire sys_rst_n = rst_n & pll_lock;

    gowin_rpll pll_inst (
        .clkout(clk_126m), 
        .clkoutd(clk_pixel), 
        .clkin(clk), 
        .lock(pll_lock)
    );

    // ==========================================
    // 2. 内存系统：真·双口 Block RAM (跨时钟域屏障)
    // ==========================================
    // 容量: 1024 个 8位字节。A口用于126M写入，B口用于25M读取
    reg [7:0] bram [0:1023];
    
    // ==========================================
    // 3. 数据采集舱 (运行在 126MHz 狂暴域 - 升级为自动循环采样)
    // ==========================================
    reg [1:0] state;
    reg [9:0] waddr;
    reg [25:0] hold_cnt; // 保持计数器：用于控制抓满后在屏幕上停留展示的时间

    always @(posedge clk_126m or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            state    <= 2'd0;
            waddr    <= 10'd0;
            hold_cnt <= 26'd0;
        end else begin
            case (state)
                2'd0: begin // 状态 0：清空地址，擦掌磨拳等待 34脚（CH0）下降沿触发
                    waddr <= 10'd0;
                    if (rx_pins[0] == 1'b0) begin
                        state <= 2'd1;
                    end
                end
                
                2'd1: begin // 状态 1：以 126MHz 极速连续抓取 640 个采样点
                    bram[waddr] <= rx_pins;
                    waddr       <= waddr + 10'd1;
                    if (waddr == 10'd639) begin
                        state    <= 2'd2; // 抓满！进入保持显示状态
                        hold_cnt <= 26'd0;
                    end
                end
                
                2'd2: begin // 状态 2：让抓到的波形在屏幕上稳定停留一会（约 0.3 秒），肉眼才看得清
                    hold_cnt <= hold_cnt + 26'd1;
                    if (hold_cnt == 26'd38_000_000) begin // 126MHz 下约 0.3 秒
                        state <= 2'd0; // 时间到！自动重置回 0，开启下一轮动态抓取
                    end
                end
                
                default: state <= 2'd0;
            endcase
        end
    end

    // ==========================================
    // 4. 显卡扫描引擎 (运行在 25.2MHz 视觉域)
    // ==========================================
    wire [9:0] pix_x, pix_y;
    wire draw_en, hsync, vsync;
    
    vga_timing vga_inst (
        .clk(clk_pixel), .rst_n(sys_rst_n), 
        .hsync(hsync), .vsync(vsync), .draw_en(draw_en), 
        .x(pix_x), .y(pix_y)
    );

    // 【显存读取】根据当前屏幕扫描的 X 坐标，提前 1 周期取出对应的波形数据
    reg [7:0] wave_data;
    always @(posedge clk_pixel) begin
        wave_data <= bram[pix_x]; 
    end

    // 【时序对齐】因为读取 BRAM 消耗了 1 个时钟，屏幕坐标必须延迟 1 拍，否则波形会错位
    reg [9:0] x_d, y_d;
    reg draw_en_d, hsync_d, vsync_d;
    reg [7:0] wave_data_prev; // 保存上一个像素的波形，用于画垂直跳变线！
    
    always @(posedge clk_pixel) begin
        x_d <= pix_x; y_d <= pix_y;
        draw_en_d <= draw_en; hsync_d <= hsync; vsync_d <= vsync;
        if (draw_en_d) wave_data_prev <= wave_data; 
    end

    // ==========================================
    // 5. 几何着色器 Shader (波形栅格化计算)
    // ==========================================
    // 将 480 像素的屏幕，切分为 8 条轨道，每条轨道高度 60 像素
    reg [2:0] ch_idx;  // 当前扫描扫描线属于哪个通道 (0~7)
    reg [5:0] ch_y;    // 扫描线在该通道内的局部 Y 坐标 (0~59)
    
    always @(*) begin
        if      (y_d <  60) begin ch_idx = 0; ch_y = y_d[5:0]; end
        else if (y_d < 120) begin ch_idx = 1; ch_y = y_d - 10'd60; end
        else if (y_d < 180) begin ch_idx = 2; ch_y = y_d - 10'd120; end
        else if (y_d < 240) begin ch_idx = 3; ch_y = y_d - 10'd180; end
        else if (y_d < 300) begin ch_idx = 4; ch_y = y_d - 10'd240; end
        else if (y_d < 360) begin ch_idx = 5; ch_y = y_d - 10'd300; end
        else if (y_d < 420) begin ch_idx = 6; ch_y = y_d - 10'd360; end
        else                begin ch_idx = 7; ch_y = y_d - 10'd420; end
    end

    wire current_bit = wave_data[ch_idx];
    wire prev_bit = wave_data_prev[ch_idx];

    reg [7:0] red, green, blue;

    always @(posedge clk_pixel) begin
        if (draw_en_d) begin
            // 背景层：绘制极客暗格坐标网 (每 50 个像素一条线)
            if (x_d % 50 == 0 || ch_y == 0 || ch_y == 59) begin
                red <= 50; green <= 50; blue <= 50; 
            end else begin
                red <= 0; green <= 0; blue <= 0; 
            end

            // 波形层：绘制高频动态信号
            if (current_bit == 1'b1 && ch_y >= 10 && ch_y <= 12) begin
                // 逻辑高电平 (画在轨道上方)
                red <= 0; green <= 255; blue <= 0;
            end 
            else if (current_bit == 1'b0 && ch_y >= 48 && ch_y <= 50) begin
                // 逻辑低电平 (画在轨道下方)
                red <= 0; green <= 255; blue <= 0;
            end 
            else if (current_bit != prev_bit && ch_y > 12 && ch_y < 48) begin
                // 垂直跳变边缘 (补齐高低电平之间的连线)
                red <= 0; green <= 255; blue <= 0;
            end
        end else begin
            red <= 0; green <= 0; blue <= 0;
        end
    end

    // ==========================================
    // 6. HDMI 发射器黑盒
    // ==========================================
    dvi_tx hdmi_inst (
        .clk_pixel(clk_pixel), .clk_5x(clk_126m), .rst_n(sys_rst_n), 
        .r(red), .g(green), .b(blue), 
        .hsync(hsync_d), .vsync(vsync_d), .draw_en(draw_en_d), 
        .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n), 
        .tmds_d_p(tmds_d_p), .tmds_d_n(tmds_d_n)
    );

    // 状态灯：LED 0 闪烁代表采样结束
    assign led[0] = ~(state == 2);
    assign led[5:1] = 5'b11111;

endmodule