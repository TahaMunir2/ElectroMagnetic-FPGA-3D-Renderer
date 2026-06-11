// ============================================================================
//  contour_hdmi_top.sv  (writable-palette, standalone board-test version)
//  ----------------------------------------------------------------------------
//  Standalone PYNQ-Z1 HDMI top for the 2D contour renderer with a RUNTIME
//  palette. Faithful copy of ray_unit_hdmi_top_d4s48 with the ray unit + 50
//  BRAMs replaced by ONE contour_unit + ONE heightmap_bram, and a palette_loader
//  that drives contour_unit's palette write port so the writable palette is
//  visible on screen with NO PS involvement.
//
//  ** For the real system **: delete u_loader and instead instantiate
//  contour_palette_axil, wiring its {pal_we,pal_idx,pal_rgb} to u_contour and
//  its AXI-Lite bus to the Zynq PS. Everything else stays the same.
//
//  Required Vivado IP: clk_wiz_1, rgb2dvi_0 (as before).
// ============================================================================

module contour_hdmi_top (
    input  logic       clk,
    input  logic       rst,
    // optional: tie to board switches to pick the palette manually (else auto)
    input  logic [1:0] sw,

    output logic       hdmi_tx_clk_p,
    output logic       hdmi_tx_clk_n,
    output logic [2:0] hdmi_tx_p,
    output logic [2:0] hdmi_tx_n
);

    localparam int W=640, H=480;
    localparam int H_FRONT=16, H_SYNC=96, H_BACK=48, H_TOTAL=W+H_FRONT+H_SYNC+H_BACK;
    localparam int V_FRONT=10, V_SYNC=2, V_BACK=33, V_TOTAL=H+V_FRONT+V_SYNC+V_BACK;
    localparam int PX_W=10, PY_W=9;

    localparam int GRID_N=64, IDX_W=6, ADDR_W=IDX_W*2, H_W=16;

    // contour latency -> video delay. Set RD_LAT to your heightmap_bram's read
    // latency (1 = simple dout<=mem[addr]; 2 = with output register).
    localparam int RD_LAT              = 1;
    localparam int RENDER_LATENCY_CORE = RD_LAT + 2;
    localparam int RENDER_LATENCY_PIX  = (RENDER_LATENCY_CORE + 3) / 4;
    localparam int FIFO_PRIME_PIX      = 8;
    localparam int VIDEO_DELAY_PIX     = RENDER_LATENCY_PIX + FIFO_PRIME_PIX;

    // set 1 to drive palette from `sw`, 0 to auto-cycle presets
    localparam logic USE_SW = 1'b0;

    logic clk_pix, clk_5x, clk_core, clk_locked;
    clk_wiz_1 u_clk_wiz (
        .clk_in1(clk), .reset(rst),
        .clk_out1(clk_pix), .clk_out2(clk_5x), .clk_out3(clk_core),
        .locked(clk_locked));

    logic rst_pix_n, rst_core_n;
    (* ASYNC_REG="TRUE" *) logic [3:0] pix_reset_sync;
    (* ASYNC_REG="TRUE" *) logic [3:0] core_reset_sync;
    always_ff @(posedge clk_pix or posedge rst or negedge clk_locked)
        if (rst || !clk_locked) pix_reset_sync <= '0;
        else pix_reset_sync <= {pix_reset_sync[2:0],1'b1};
    always_ff @(posedge clk_core or posedge rst or negedge clk_locked)
        if (rst || !clk_locked) core_reset_sync <= '0;
        else core_reset_sync <= {core_reset_sync[2:0],1'b1};
    assign rst_pix_n = pix_reset_sync[3];
    assign rst_core_n = core_reset_sync[3];

    // core-domain 800x525 timing, 1 active pixel / 4 core cycles
    logic [1:0] core_pix_phase; logic [9:0] core_sx, core_sy;
    logic core_active; logic [PX_W-1:0] gen_x; logic [PY_W-1:0] gen_y; logic gen_valid;
    assign core_active = (core_sx<W)&&(core_sy<H);
    assign gen_x = core_sx[PX_W-1:0];
    assign gen_y = core_sy[PY_W-1:0];
    assign gen_valid = (core_pix_phase==2'd0)&&core_active;
    always_ff @(posedge clk_core)
        if (!rst_core_n) begin core_pix_phase<=2'd0; core_sx<='0; core_sy<='0; end
        else begin
            core_pix_phase <= core_pix_phase + 2'd1;
            if (core_pix_phase==2'd0) begin
                if (core_sx==H_TOTAL-1) begin
                    core_sx<='0;
                    core_sy<=(core_sy==V_TOTAL-1)?'0:core_sy+1'b1;
                end else core_sx<=core_sx+1'b1;
            end
        end

    // single shared heightmap BRAM
    logic [ADDR_W-1:0] c_addr; logic c_re; logic signed [H_W-1:0] c_dout;
    heightmap_bram #(.ADDR_W(ADDR_W), .DATA_W(H_W)) u_bram (
        .clk(clk_core), .addr(c_addr), .re(c_re), .dout(c_dout));

    // palette write port (driven by loader here; by AXI-Lite slave in real sys)
    logic        pal_we; logic [3:0] pal_idx; logic [23:0] pal_rgb;
    palette_loader #(.CYCLE_LOG2(27)) u_loader (
        .clk(clk_core), .rst_n(rst_core_n),
        .use_sel_in(USE_SW), .sel_in(sw),
        .pal_we(pal_we), .pal_idx(pal_idx), .pal_rgb(pal_rgb));

    // contour renderer
    logic [7:0] c_r,c_g,c_b; logic [PX_W-1:0] c_px; logic [PY_W-1:0] c_py; logic c_valid;
    contour_unit #(.W(W), .H(H), .GRID_N(GRID_N), .H_W(H_W), .H_I(2), .RD_LAT(RD_LAT))
    u_contour (
        .clk(clk_core), .rst_n(rst_core_n), .en(1'b1),
        .px_in(gen_x), .py_in(gen_y), .valid_in(gen_valid),
        .bram_addr(c_addr), .bram_re(c_re), .bram_dout(c_dout),
        .pal_we(pal_we), .pal_idx(pal_idx), .pal_rgb(pal_rgb),
        .r_out(c_r), .g_out(c_g), .b_out(c_b),
        .px_out(c_px), .py_out(c_py), .valid_out(c_valid));

    // async FIFO core->pix
    logic fifo_wr_en, fifo_full, fifo_rd_en, fifo_empty;
    logic [23:0] fifo_din, fifo_dout; logic wr_rst_busy, rd_rst_busy;
    assign fifo_wr_en = c_valid & ~fifo_full & ~wr_rst_busy;
    assign fifo_din = {c_r,c_g,c_b};
    xpm_fifo_async #(
        .FIFO_MEMORY_TYPE("block"), .FIFO_WRITE_DEPTH(1024),
        .WRITE_DATA_WIDTH(24), .READ_DATA_WIDTH(24),
        .READ_MODE("fwft"), .FIFO_READ_LATENCY(0),
        .PROG_FULL_THRESH(768), .USE_ADV_FEATURES("0000"),
        .CDC_SYNC_STAGES(2), .RELATED_CLOCKS(0)
    ) u_fifo (
        .wr_clk(clk_core), .rst(~rst_core_n), .wr_en(fifo_wr_en),
        .din(fifo_din), .full(fifo_full), .prog_full(), .wr_rst_busy(wr_rst_busy),
        .rd_clk(clk_pix), .rd_en(fifo_rd_en), .dout(fifo_dout),
        .empty(fifo_empty), .rd_rst_busy(rd_rst_busy),
        .sleep(1'b0), .injectsbiterr(1'b0), .injectdbiterr(1'b0),
        .almost_empty(), .almost_full(), .data_valid(), .dbiterr(),
        .overflow(), .prog_empty(), .rd_data_count(), .wr_data_count(),
        .sbiterr(), .underflow(), .wr_ack());

    logic [9:0] sx,sy; logic hsync,vsync,active_video;
    video_timing_640x480 u_timing (
        .clk_pix(clk_pix), .rst_n(rst_pix_n),
        .sx(sx), .sy(sy), .hsync(hsync), .vsync(vsync), .active_video(active_video));

    logic hdmi_de, hdmi_hsync, hdmi_vsync; logic [7:0] hdmi_r,hdmi_g,hdmi_b;
    logic [VIDEO_DELAY_PIX-1:0] hsync_pipe, vsync_pipe, de_pipe;
    logic delayed_active, fifo_underflow;
    assign delayed_active = de_pipe[VIDEO_DELAY_PIX-1];
    assign fifo_rd_en = delayed_active & ~fifo_empty & ~rd_rst_busy;
    assign fifo_underflow = delayed_active & (fifo_empty | rd_rst_busy);
    always_ff @(posedge clk_pix)
        if (!rst_pix_n) begin
            hsync_pipe<='1; vsync_pipe<='1; de_pipe<='0;
            hdmi_hsync<=1'b1; hdmi_vsync<=1'b1; hdmi_de<=1'b0;
            hdmi_r<=8'd0; hdmi_g<=8'd0; hdmi_b<=8'd0;
        end else begin
            hsync_pipe <= {hsync_pipe[VIDEO_DELAY_PIX-2:0], hsync};
            vsync_pipe <= {vsync_pipe[VIDEO_DELAY_PIX-2:0], vsync};
            de_pipe    <= {de_pipe[VIDEO_DELAY_PIX-2:0], active_video};
            hdmi_hsync <= hsync_pipe[VIDEO_DELAY_PIX-1];
            hdmi_vsync <= vsync_pipe[VIDEO_DELAY_PIX-1];
            hdmi_de    <= delayed_active;
            if (fifo_rd_en) begin
                hdmi_r<=fifo_dout[23:16]; hdmi_g<=fifo_dout[15:8]; hdmi_b<=fifo_dout[7:0];
            end else if (fifo_underflow) begin
                hdmi_r<=8'hff; hdmi_g<=8'h00; hdmi_b<=8'hff;
            end else begin
                hdmi_r<=8'd0; hdmi_g<=8'd0; hdmi_b<=8'd0;
            end
        end

    rgb2dvi_0 u_rgb2dvi (
        .TMDS_Clk_p(hdmi_tx_clk_p), .TMDS_Clk_n(hdmi_tx_clk_n),
        .TMDS_Data_p(hdmi_tx_p), .TMDS_Data_n(hdmi_tx_n),
        .aRst(!rst_pix_n),
        .vid_pData({hdmi_r, hdmi_b, hdmi_g}),
        .vid_pVDE(hdmi_de), .vid_pHSync(hdmi_hsync), .vid_pVSync(hdmi_vsync),
        .PixelClk(clk_pix), .SerialClk(clk_5x));

endmodule
