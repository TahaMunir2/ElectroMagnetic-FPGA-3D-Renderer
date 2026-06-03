// PYNQ-Z1 HDMI wrapper for the ray renderer -- DESIGN 2 (half-rate core).
//
// Architecture change vs Design 1:
//   - The renderer core (ray_unit2) runs at 2x the pixel clock (50 MHz) and
//     produces 1 pixel every 2 core cycles  => 25 Mpix/s average.
//   - An asynchronous FIFO crosses from the 50 MHz render domain to the
//     25 MHz pixel/scanout domain.
//   - The core-domain pixel generator includes HDMI blanking, so the renderer
//     produces active pixels at the same average rate that HDMI consumes them.
//   - The FIFO bridges render latency and the 50 MHz / 25 MHz clock phase.
//
// Required Vivado IP:
//   - clk_wiz_0:
//       input  clk_in1  = 125 MHz PL clock
//       output clk_out1 = 25 MHz  pixel clock     (clk_pix)
//       output clk_out2 = 125 MHz serial clock    (clk_5x)
//       output clk_out3 = 50 MHz  render clock     (clk_core)   <-- NEW
//   - rgb2dvi_0: as before
//   - xpm_fifo_async (inferred via XPM macro, no IP needed)

module ray_unit_hdmi_top_d2 (
    input  logic       clk,
    input  logic       rst,

    output logic       hdmi_tx_clk_p,
    output logic       hdmi_tx_clk_n,
    output logic [2:0] hdmi_tx_p,
    output logic [2:0] hdmi_tx_n
);

    localparam int W       = 640;
    localparam int H       = 480;
    localparam int H_FRONT = 16;
    localparam int H_SYNC  = 96;
    localparam int H_BACK  = 48;
    localparam int H_TOTAL = W + H_FRONT + H_SYNC + H_BACK;
    localparam int V_FRONT = 10;
    localparam int V_SYNC  = 2;
    localparam int V_BACK  = 33;
    localparam int V_TOTAL = H + V_FRONT + V_SYNC + V_BACK;
    localparam int PX_W    = 10;
    localparam int PY_W    = 9;

    localparam int GRID_N  = 64;
    localparam int IDX_W   = 6;
    localparam int ADDR_W  = IDX_W * 2;

    localparam int N_STEPS = 48;
    localparam int H_W     = 16;
    localparam int DIR_W   = 16;
    localparam int POS_W   = 16;
    localparam int RENDER_LATENCY_CORE = 4 + 5*N_STEPS + 6 + 5;
    localparam int RENDER_LATENCY_PIX  = (RENDER_LATENCY_CORE + 1) / 2;

    localparam logic signed [DIR_W-1:0] ZERO = 16'sd0;

    // Camera: close above the -X/-Y side, looking diagonally toward map centre.
    localparam logic signed [POS_W-1:0] OX = -16'sd2867;
    localparam logic signed [POS_W-1:0] OY = -16'sd2867;
    localparam logic signed [POS_W-1:0] OZ =  16'sd3686;
    localparam logic signed [DIR_W-1:0] FWD_X   =  16'sd4096;
    localparam logic signed [DIR_W-1:0] FWD_Y   =  16'sd4096;
    localparam logic signed [DIR_W-1:0] FWD_Z   = -16'sd5793;
    localparam logic signed [DIR_W-1:0] RIGHT_X =  16'sd5793;
    localparam logic signed [DIR_W-1:0] RIGHT_Y = -16'sd5793;
    localparam logic signed [DIR_W-1:0] RIGHT_Z =  16'sd0;
    localparam logic signed [DIR_W-1:0] UP_X    =  16'sd4096;
    localparam logic signed [DIR_W-1:0] UP_Y    =  16'sd4096;
    localparam logic signed [DIR_W-1:0] UP_Z    =  16'sd5793;
    localparam logic signed [DIR_W-1:0] SUN_D   =  16'sd5793;

    // ---------------------------------------------------------------
    //  Clocks
    // ---------------------------------------------------------------
    logic clk_pix;     // 25 MHz  - HDMI scanout
    logic clk_5x;      // 125 MHz - TMDS serial
    logic clk_core;    // 50 MHz  - renderer (NEW)
    logic clk_locked;

    clk_wiz_1 u_clk_wiz (
        .clk_in1  (clk),
        .reset    (rst),
        .clk_out1 (clk_pix),
        .clk_out2 (clk_5x),
        .clk_out3 (clk_core),     // add this output in the clk_wiz GUI
        .locked   (clk_locked)
    );

    logic rst_pix_n;
    logic rst_core_n;
    assign rst_pix_n  = ~rst & clk_locked;
    assign rst_core_n = ~rst & clk_locked;

    // ===============================================================
    //  RENDER DOMAIN  (clk_core, 50 MHz)
    // ===============================================================

    // Core-domain copy of the 640x480 timing. It advances once per pixel
    // period on the 50 MHz renderer clock and feeds only active pixels.
    logic            core_pix_phase;
    logic [9:0]      core_sx;
    logic [9:0]      core_sy;
    logic            core_active;
    logic [PX_W-1:0] gen_x;
    logic [PY_W-1:0] gen_y;
    logic            gen_valid;     // one-cycle pixel feed strobe

    assign core_active = (core_sx < W) && (core_sy < H);
    assign gen_x       = core_sx[PX_W-1:0];
    assign gen_y       = core_sy[PY_W-1:0];
    assign gen_valid   = (core_pix_phase == 1'b0) && core_active;

    always_ff @(posedge clk_core) begin
        if (!rst_core_n) begin
            core_pix_phase <= 1'b0;
            core_sx        <= '0;
            core_sy        <= '0;
        end else begin
            core_pix_phase <= ~core_pix_phase;
            if (core_pix_phase == 1'b0) begin
                if (core_sx == H_TOTAL-1) begin
                    core_sx <= '0;
                    core_sy <= (core_sy == V_TOTAL-1) ? '0 : core_sy + 1'b1;
                end else begin
                    core_sx <= core_sx + 1'b1;
                end
            end
        end
    end

    // Heightmap BRAMs - 24 marcher + 2 normal, clocked on clk_core.
    logic [ADDR_W-1:0]     mb_addr [N_STEPS/2];
    logic                  mb_re   [N_STEPS/2];
    logic signed [H_W-1:0] mb_dout [N_STEPS/2];
    logic [ADDR_W-1:0]     nb_addr [2];
    logic                  nb_re   [2];
    logic signed [H_W-1:0] nb_dout [2];

    genvar gi;
    generate
        for (gi = 0; gi < N_STEPS/2; gi++) begin : g_marcher_bram
            heightmap_bram #(.ADDR_W(ADDR_W), .DATA_W(H_W)) u_bram (
                .clk(clk_core), .addr(mb_addr[gi]), .re(mb_re[gi]), .dout(mb_dout[gi]));
        end
        for (gi = 0; gi < 2; gi++) begin : g_normal_bram
            heightmap_bram #(.ADDR_W(ADDR_W), .DATA_W(H_W)) u_bram (
                .clk(clk_core), .addr(nb_addr[gi]), .re(nb_re[gi]), .dout(nb_dout[gi]));
        end
    endgenerate

    logic [7:0]      ray_r, ray_g, ray_b;
    logic [PX_W-1:0] ray_px;
    logic [PY_W-1:0] ray_py;
    logic            ray_valid;

    ray_unit2 #(
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

    // ===============================================================
    //  ASYNC FIFO  (write: clk_core / read: clk_pix)
    //  Width = 24 (RGB).  Depth 1024 is enough for latency/phase buffering
    //  because the producer now observes blanking and matches scanout rate.
    // ===============================================================
    logic        fifo_wr_en;
    logic [23:0] fifo_din;
    logic        fifo_full;
    logic        fifo_rd_en;
    logic [23:0] fifo_dout;
    logic        fifo_empty;
    logic        wr_rst_busy;
    logic        rd_rst_busy;

    // Only write a finished pixel when the FIFO is ready (not in reset).
    assign fifo_wr_en = ray_valid & ~fifo_full & ~wr_rst_busy;
    assign fifo_din   = {ray_r, ray_g, ray_b};

    xpm_fifo_async #(
        .FIFO_MEMORY_TYPE  ("block"),
        .FIFO_WRITE_DEPTH  (1024),
        .WRITE_DATA_WIDTH  (24),
        .READ_DATA_WIDTH   (24),
        .READ_MODE         ("fwft"),
        .FIFO_READ_LATENCY (0),
        .PROG_FULL_THRESH  (768),
        .USE_ADV_FEATURES  ("0000"),
        .CDC_SYNC_STAGES   (2),
        .RELATED_CLOCKS    (0)
    ) u_fifo (
        .wr_clk        (clk_core),
        .rst           (~rst_core_n),
        .wr_en         (fifo_wr_en),
        .din           (fifo_din),
        .full          (fifo_full),
        .prog_full     (),
        .wr_rst_busy   (wr_rst_busy),
        .rd_clk        (clk_pix),
        .rd_en         (fifo_rd_en),
        .dout          (fifo_dout),
        .empty         (fifo_empty),
        .rd_rst_busy   (rd_rst_busy),
        // unused
        .sleep(1'b0), .injectsbiterr(1'b0), .injectdbiterr(1'b0),
        .almost_empty(), .almost_full(), .data_valid(), .dbiterr(),
        .overflow(), .prog_empty(), .rd_data_count(), .wr_data_count(),
        .sbiterr(), .underflow(), .wr_ack()
    );

    // ===============================================================
    //  SCANOUT DOMAIN  (clk_pix, 25 MHz)
    // ===============================================================
    logic [9:0] sx, sy;
    logic       hsync, vsync, active_video;

    video_timing_640x480 u_timing (
        .clk_pix(clk_pix), .rst_n(rst_pix_n),
        .sx(sx), .sy(sy), .hsync(hsync), .vsync(vsync),
        .active_video(active_video)
    );

    logic       hdmi_de;
    logic       hdmi_hsync, hdmi_vsync;
    logic [7:0] hdmi_r, hdmi_g, hdmi_b;
    logic [RENDER_LATENCY_PIX-1:0] hsync_pipe;
    logic [RENDER_LATENCY_PIX-1:0] vsync_pipe;
    logic [RENDER_LATENCY_PIX-1:0] de_pipe;

    assign fifo_rd_en = de_pipe[RENDER_LATENCY_PIX-1] & ~fifo_empty & ~rd_rst_busy;

    always_ff @(posedge clk_pix) begin
        if (!rst_pix_n) begin
            hsync_pipe <= '1;
            vsync_pipe <= '1;
            de_pipe    <= '0;
            hdmi_hsync <= 1'b1;
            hdmi_vsync <= 1'b1;
            hdmi_de    <= 1'b0;
            hdmi_r     <= 8'd0;
            hdmi_g     <= 8'd0;
            hdmi_b     <= 8'd0;
        end else begin
            hsync_pipe <= {hsync_pipe[RENDER_LATENCY_PIX-2:0], hsync};
            vsync_pipe <= {vsync_pipe[RENDER_LATENCY_PIX-2:0], vsync};
            de_pipe    <= {de_pipe[RENDER_LATENCY_PIX-2:0], active_video};

            hdmi_hsync <= hsync_pipe[RENDER_LATENCY_PIX-1];
            hdmi_vsync <= vsync_pipe[RENDER_LATENCY_PIX-1];
            hdmi_de    <= fifo_rd_en;

            if (fifo_rd_en) begin
                hdmi_r <= fifo_dout[23:16];
                hdmi_g <= fifo_dout[15:8];
                hdmi_b <= fifo_dout[7:0];
            end else begin
                hdmi_r <= 8'd0;
                hdmi_g <= 8'd0;
                hdmi_b <= 8'd0;
            end
        end
    end

    rgb2dvi_0 u_rgb2dvi (
        .TMDS_Clk_p  (hdmi_tx_clk_p),
        .TMDS_Clk_n  (hdmi_tx_clk_n),
        .TMDS_Data_p (hdmi_tx_p),
        .TMDS_Data_n (hdmi_tx_n),
        .aRst        (!rst_pix_n),
        .vid_pData   ({hdmi_r, hdmi_b, hdmi_g}),
        .vid_pVDE    (hdmi_de),
        .vid_pHSync  (hdmi_hsync),
        .vid_pVSync  (hdmi_vsync),
        .PixelClk    (clk_pix),
        .SerialClk   (clk_5x)
    );

endmodule
