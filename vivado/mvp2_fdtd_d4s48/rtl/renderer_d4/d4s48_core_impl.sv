`timescale 1ns/1ps
// ============================================================================
//  d4s48_renderer_core_bd.sv
//  D4S48 3D ray-march renderer as a BD core for the FDTD pipeline. This is
//  Cyril's ray_unit_hdmi_top_d4s48 with the standalone bits removed so it drops
//  into our block design like contour_renderer_core_bd did:
//    - clk_wiz removed: clk_pix (25) + clk_core (100) come from the BD clk_wiz.
//    - rgb2dvi removed: outputs vid_pData/VDE/HSync/VSync to the BD's rgb2dvi.
//    - the read-only heightmap_bram is replaced by 50x heightmap_bram_d4
//      (dual-clock writable, 8-bit storage); the FDTD bridge writes them via
//      hm_we/hm_waddr/hm_wdata @ clk_pix, broadcast to all copies.
//    - vblank exported so the bridge writes the heightmap during blanking.
//  Camera basis is fixed (Cyril's isometric view). N_STEPS=48, GRID_N=64.
// ============================================================================
module d4s48_core_impl (
    input  wire        clk_pix,
    input  wire        clk_core,
    input  wire        rst_pix_n,

    // FDTD heightmap write port (from the bridge, clk_pix domain, 64x64)
    input  wire        hm_we,
    input  wire [11:0] hm_waddr,
    input  wire signed [15:0] hm_wdata,
    output wire        vblank,

    // HDMI video out (clk_pix, to rgb2dvi)
    output wire [23:0] vid_pData,
    output wire        vid_pVDE,
    output wire        vid_pHSync,
    output wire        vid_pVSync
);
    localparam int W = 640, H = 480;
    localparam int H_FRONT = 16, H_SYNC = 96, H_BACK = 48;
    localparam int H_TOTAL = W + H_FRONT + H_SYNC + H_BACK;
    localparam int V_FRONT = 10, V_SYNC = 2, V_BACK = 33;
    localparam int V_TOTAL = H + V_FRONT + V_SYNC + V_BACK;
    localparam int PX_W = 10, PY_W = 9;
    localparam int GRID_N = 64, IDX_W = 6, ADDR_W = IDX_W*2;
    localparam int N_STEPS = 48, H_W = 16, DIR_W = 16, POS_W = 16;

    localparam int RENDER_LATENCY_CORE = 4 + 11*N_STEPS + 5 + 5;
    localparam int RENDER_LATENCY_PIX  = (RENDER_LATENCY_CORE + 3) / 4;
    localparam int FIFO_PRIME_PIX      = 8;
    localparam int VIDEO_DELAY_PIX     = RENDER_LATENCY_PIX + FIFO_PRIME_PIX;

    // fixed isometric camera (Cyril's basis)
    localparam logic signed [DIR_W-1:0] ZERO = 16'sd0;
    localparam logic signed [POS_W-1:0] OX = -16'sd2867, OY = -16'sd2867, OZ = 16'sd3686;
    localparam logic signed [DIR_W-1:0] FWD_X = 16'sd4096, FWD_Y = 16'sd4096, FWD_Z = -16'sd5793;
    localparam logic signed [DIR_W-1:0] RIGHT_X = 16'sd5793, RIGHT_Y = -16'sd5793, RIGHT_Z = 16'sd0;
    localparam logic signed [DIR_W-1:0] UP_X = 16'sd4096, UP_Y = 16'sd4096, UP_Z = 16'sd5793;
    localparam logic signed [DIR_W-1:0] SUN_D = 16'sd5793;

    // ---- reset sync into the core (100 MHz) domain ----
    logic rst_core_n;
    (* ASYNC_REG = "TRUE" *) logic [2:0] core_rst_sync;
    always_ff @(posedge clk_core or negedge rst_pix_n) begin
        if (!rst_pix_n) core_rst_sync <= '0;
        else            core_rst_sync <= {core_rst_sync[1:0], 1'b1};
    end
    assign rst_core_n = core_rst_sync[2];

    // ---- core-domain VGA generator: advance once every 4 core cycles ----
    logic [1:0]      core_pix_phase;
    logic [9:0]      core_sx, core_sy;
    logic            core_active;
    logic [PX_W-1:0] gen_x;
    logic [PY_W-1:0] gen_y;
    logic            gen_valid;
    assign core_active = (core_sx < W) && (core_sy < H);
    assign gen_x     = core_sx[PX_W-1:0];
    assign gen_y     = core_sy[PY_W-1:0];
    assign gen_valid = (core_pix_phase == 2'd0) && core_active;
    always_ff @(posedge clk_core) begin
        if (!rst_core_n) begin
            core_pix_phase <= 2'd0; core_sx <= '0; core_sy <= '0;
        end else begin
            core_pix_phase <= core_pix_phase + 2'd1;
            if (core_pix_phase == 2'd0) begin
                if (core_sx == H_TOTAL-1) begin
                    core_sx <= '0;
                    core_sy <= (core_sy == V_TOTAL-1) ? '0 : core_sy + 1'b1;
                end else core_sx <= core_sx + 1'b1;
            end
        end
    end

    // ---- 50 writable heightmap copies (write @clk_pix broadcast, read @clk_core) ----
    logic [ADDR_W-1:0]     mb_addr [N_STEPS];
    logic                  mb_re   [N_STEPS];
    logic signed [H_W-1:0] mb_dout [N_STEPS];
    logic [ADDR_W-1:0]     nb_addr [2];
    logic                  nb_re   [2];
    logic signed [H_W-1:0] nb_dout [2];
    genvar gi;
    generate
        for (gi = 0; gi < N_STEPS; gi++) begin : g_marcher_bram
            heightmap_bram_d4 #(.ADDR_W(ADDR_W), .DATA_W(H_W)) u_bram (
                .wr_clk(clk_pix), .we(hm_we), .waddr(hm_waddr), .wdata(hm_wdata),
                .rd_clk(clk_core), .addr(mb_addr[gi]), .re(1'b1), .dout(mb_dout[gi]));
        end
        for (gi = 0; gi < 2; gi++) begin : g_normal_bram
            heightmap_bram_d4 #(.ADDR_W(ADDR_W), .DATA_W(H_W)) u_bram (
                .wr_clk(clk_pix), .we(hm_we), .waddr(hm_waddr), .wdata(hm_wdata),
                .rd_clk(clk_core), .addr(nb_addr[gi]), .re(1'b1), .dout(nb_dout[gi]));
        end
    endgenerate

    // ---- ray-march renderer core (100 MHz) ----
    logic [7:0]      ray_r, ray_g, ray_b;
    logic [PX_W-1:0] ray_px;
    logic [PY_W-1:0] ray_py;
    logic            ray_valid;
    ray_unit4 #(
        .W(W), .H(H), .GRID_N(GRID_N), .N_STEPS(N_STEPS),
        .H_W(H_W), .H_I(2), .DIR_W(DIR_W), .DIR_I(2), .POS_W(POS_W), .POS_I(2)
    ) u_ray_unit (
        .clk(clk_core), .rst_n(rst_core_n), .en(1'b1),
        .Ox(OX), .Oy(OY), .Oz(OZ),
        .fwd_x(FWD_X), .fwd_y(FWD_Y), .fwd_z(FWD_Z),
        .right_x(RIGHT_X), .right_y(RIGHT_Y), .right_z(RIGHT_Z),
        .up_x(UP_X), .up_y(UP_Y), .up_z(UP_Z),
        .sun_dx(ZERO), .sun_dy(SUN_D), .sun_dz(SUN_D),
        .px_in(gen_x), .py_in(gen_y), .valid_in(gen_valid),
        .marcher_bram_addr(mb_addr), .marcher_bram_re(mb_re), .marcher_bram_dout(mb_dout),
        .normal_bram_addr(nb_addr), .normal_bram_re(nb_re), .normal_bram_dout(nb_dout),
        .r_out(ray_r), .g_out(ray_g), .b_out(ray_b),
        .px_out(ray_px), .py_out(ray_py), .valid_out(ray_valid)
    );

    // ---- async FIFO: core (100) -> pix (25) ----
    logic        fifo_wr_en, fifo_full, fifo_rd_en, fifo_empty, wr_rst_busy, rd_rst_busy;
    logic [23:0] fifo_din, fifo_dout;
    assign fifo_wr_en = ray_valid & ~fifo_full & ~wr_rst_busy;
    assign fifo_din   = {ray_r, ray_g, ray_b};
    xpm_fifo_async #(
        .FIFO_MEMORY_TYPE("block"), .FIFO_WRITE_DEPTH(1024),
        .WRITE_DATA_WIDTH(24), .READ_DATA_WIDTH(24), .READ_MODE("fwft"),
        .FIFO_READ_LATENCY(0), .PROG_FULL_THRESH(768),
        .USE_ADV_FEATURES("0000"), .CDC_SYNC_STAGES(2), .RELATED_CLOCKS(0)
    ) u_fifo (
        .wr_clk(clk_core), .rst(~rst_core_n), .wr_en(fifo_wr_en), .din(fifo_din),
        .full(fifo_full), .prog_full(), .wr_rst_busy(wr_rst_busy),
        .rd_clk(clk_pix), .rd_en(fifo_rd_en), .dout(fifo_dout), .empty(fifo_empty),
        .rd_rst_busy(rd_rst_busy),
        .sleep(1'b0), .injectsbiterr(1'b0), .injectdbiterr(1'b0),
        .almost_empty(), .almost_full(), .data_valid(), .dbiterr(),
        .overflow(), .prog_empty(), .rd_data_count(), .wr_data_count(),
        .sbiterr(), .underflow(), .wr_ack()
    );

    // ---- pixel-domain VGA timing + latency alignment ----
    logic [9:0] sx, sy;
    logic       hsync, vsync, active_video;
    design1_video_timing_640x480 u_timing (
        .clk_pix(clk_pix), .rst_n(rst_pix_n),
        .sx(sx), .sy(sy), .hsync(hsync), .vsync(vsync), .active_video(active_video));
    assign vblank = (sy >= H[9:0]);

    logic       hdmi_de, hdmi_hsync, hdmi_vsync;
    logic [7:0] hdmi_r, hdmi_g, hdmi_b;
    logic [VIDEO_DELAY_PIX-1:0] hsync_pipe, vsync_pipe, de_pipe;
    logic delayed_active, fifo_underflow;
    assign delayed_active = de_pipe[VIDEO_DELAY_PIX-1];
    assign fifo_rd_en     = delayed_active & ~fifo_empty & ~rd_rst_busy;
    assign fifo_underflow = delayed_active & (fifo_empty | rd_rst_busy);
    always_ff @(posedge clk_pix) begin
        if (!rst_pix_n) begin
            hsync_pipe <= '1; vsync_pipe <= '1; de_pipe <= '0;
            hdmi_hsync <= 1'b1; hdmi_vsync <= 1'b1; hdmi_de <= 1'b0;
            hdmi_r <= 8'd0; hdmi_g <= 8'd0; hdmi_b <= 8'd0;
        end else begin
            hsync_pipe <= {hsync_pipe[VIDEO_DELAY_PIX-2:0], hsync};
            vsync_pipe <= {vsync_pipe[VIDEO_DELAY_PIX-2:0], vsync};
            de_pipe    <= {de_pipe[VIDEO_DELAY_PIX-2:0], active_video};
            hdmi_hsync <= hsync_pipe[VIDEO_DELAY_PIX-1];
            hdmi_vsync <= vsync_pipe[VIDEO_DELAY_PIX-1];
            hdmi_de    <= delayed_active;
            if (fifo_rd_en) begin
                hdmi_r <= fifo_dout[23:16]; hdmi_g <= fifo_dout[15:8]; hdmi_b <= fifo_dout[7:0];
            end else if (fifo_underflow) begin
                hdmi_r <= 8'hff; hdmi_g <= 8'h00; hdmi_b <= 8'hff;   // magenta = underflow
            end else begin
                hdmi_r <= 8'd0; hdmi_g <= 8'd0; hdmi_b <= 8'd0;
            end
        end
    end

    assign vid_pData  = {hdmi_r, hdmi_b, hdmi_g};   // {R,B,G} for rgb2dvi (matches contour)
    assign vid_pVDE   = hdmi_de;
    assign vid_pHSync = hdmi_hsync;
    assign vid_pVSync = hdmi_vsync;
endmodule
