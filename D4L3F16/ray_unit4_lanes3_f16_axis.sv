// ============================================================================
//  ray_unit4_lanes3_f16_axis.sv
//  ----------------------------------------------------------------------------
//  Three column-interleaved 16-cycle folded Design4 lanes.
//
//  Lane L renders columns x where x mod 3 == L.  A new column triple is issued
//  every 16 core cycles.  The three aligned lane outputs are re-serialized into
//  raster order and emitted as a sparse AXI4-Stream-style RGB stream for an
//  AXI VDMA S2MM framebuffer writer.
//
//  This is the render-to-framebuffer side of the architecture.  HDMI scan-out
//  should be handled by a separate VDMA MM2S path clocked by video timing.
// ============================================================================

module ray_unit4_lanes3_f16_axis #(
    parameter int W           = 640,
    parameter int H           = 480,
    parameter int LANES       = 3,
    parameter int FOLD        = 16,
    parameter int RAY_LATENCY = 4,

    parameter int GRID_N      = 64,
    parameter int IDX_W       = $clog2(GRID_N),
    parameter int ADDR_W      = IDX_W * 2,

    parameter int N_STEPS     = 48,
    parameter int MARCH_PORTS = 12,
    parameter int NORMAL_PORTS = 2,

    parameter int H_W         = 16,
    parameter int DIR_W       = 16,
    parameter int POS_W       = 16,
    parameter int PX_W        = $clog2(W),
    parameter int PY_W        = $clog2(H)
)(
    input  logic                    clk,
    input  logic                    rst_n,

    input  logic signed [POS_W-1:0] Ox,
    input  logic signed [POS_W-1:0] Oy,
    input  logic signed [POS_W-1:0] Oz,
    input  logic signed [DIR_W-1:0] fwd_x,
    input  logic signed [DIR_W-1:0] fwd_y,
    input  logic signed [DIR_W-1:0] fwd_z,
    input  logic signed [DIR_W-1:0] right_x,
    input  logic signed [DIR_W-1:0] right_y,
    input  logic signed [DIR_W-1:0] right_z,
    input  logic signed [DIR_W-1:0] up_x,
    input  logic signed [DIR_W-1:0] up_y,
    input  logic signed [DIR_W-1:0] up_z,
    input  logic signed [DIR_W-1:0] sun_dx,
    input  logic signed [DIR_W-1:0] sun_dy,
    input  logic signed [DIR_W-1:0] sun_dz,

    output logic [23:0]             m_axis_tdata,
    output logic                    m_axis_tvalid,
    input  logic                    m_axis_tready,
    output logic                    m_axis_tuser,
    output logic                    m_axis_tlast,
    output logic [PX_W-1:0]         m_axis_x,
    output logic [PY_W-1:0]         m_axis_y,

    output logic                    frame_start_pulse,
    output logic                    frame_done_pulse,
    output logic                    reorder_overflow
);

    localparam int FEED_PHASE = FOLD - RAY_LATENCY;

    logic [PX_W-1:0] lane_px       [LANES];
    logic [PY_W-1:0] lane_py       [LANES];
    logic            lane_in_valid [LANES];

    logic [7:0]      lane_r        [LANES];
    logic [7:0]      lane_g        [LANES];
    logic [7:0]      lane_b        [LANES];
    logic [PX_W-1:0] lane_px_out   [LANES];
    logic [PY_W-1:0] lane_py_out   [LANES];
    logic            lane_out_valid[LANES];
    logic [$clog2(FOLD)-1:0] lane_phase [LANES];

    genvar li;
    generate
        for (li = 0; li < LANES; li++) begin : g_lane
            logic [ADDR_W-1:0]     mb_addr [MARCH_PORTS];
            logic                  mb_re   [MARCH_PORTS];
            logic signed [H_W-1:0] mb_dout [MARCH_PORTS];
            logic [ADDR_W-1:0]     nb_addr [NORMAL_PORTS];
            logic                  nb_re   [NORMAL_PORTS];
            logic signed [H_W-1:0] nb_dout [NORMAL_PORTS];

            ray_unit4_f16 #(
                .W           (W),
                .H           (H),
                .GRID_N      (GRID_N),
                .N_STEPS     (N_STEPS),
                .H_W         (H_W),
                .H_I         (2),
                .DIR_W       (DIR_W),
                .DIR_I       (2),
                .POS_W       (POS_W),
                .POS_I       (2),
                .PX_W        (PX_W),
                .PY_W        (PY_W),
                .FOLD        (FOLD),
                .MARCH_PORTS (MARCH_PORTS)
            ) u_lane (
                .clk                (clk),
                .rst_n              (rst_n),
                .en                 (1'b1),
                .Ox                 (Ox),
                .Oy                 (Oy),
                .Oz                 (Oz),
                .fwd_x              (fwd_x),
                .fwd_y              (fwd_y),
                .fwd_z              (fwd_z),
                .right_x            (right_x),
                .right_y            (right_y),
                .right_z            (right_z),
                .up_x               (up_x),
                .up_y               (up_y),
                .up_z               (up_z),
                .sun_dx             (sun_dx),
                .sun_dy             (sun_dy),
                .sun_dz             (sun_dz),
                .px_in              (lane_px[li]),
                .py_in              (lane_py[li]),
                .valid_in           (lane_in_valid[li]),
                .marcher_bram_addr  (mb_addr),
                .marcher_bram_re    (mb_re),
                .marcher_bram_dout  (mb_dout),
                .normal_bram_addr   (nb_addr),
                .normal_bram_re     (nb_re),
                .normal_bram_dout   (nb_dout),
                .r_out              (lane_r[li]),
                .g_out              (lane_g[li]),
                .b_out              (lane_b[li]),
                .px_out             (lane_px_out[li]),
                .py_out             (lane_py_out[li]),
                .valid_out          (lane_out_valid[li]),
                .fold_phase         (lane_phase[li])
            );

            for (genvar mi = 0; mi < MARCH_PORTS; mi++) begin : g_march_bram
                heightmap_bram #(
                    .ADDR_W        (ADDR_W),
                    .DATA_W        (H_W),
                    .USE_INIT_FILE (1'b0),
                    .USE_MOCK_DATA (1'b1)
                ) u_bram (
                    .clk  (clk),
                    .addr (mb_addr[mi]),
                    .re   (1'b1),
                    .dout (mb_dout[mi])
                );
            end

            for (genvar ni = 0; ni < NORMAL_PORTS; ni++) begin : g_normal_bram
                heightmap_bram #(
                    .ADDR_W        (ADDR_W),
                    .DATA_W        (H_W),
                    .USE_INIT_FILE (1'b0),
                    .USE_MOCK_DATA (1'b1)
                ) u_bram (
                    .clk  (clk),
                    .addr (nb_addr[ni]),
                    .re   (1'b1),
                    .dout (nb_dout[ni])
                );
            end
        end
    endgenerate

    logic [PX_W-1:0] issue_x;
    logic [PY_W-1:0] issue_y;
    logic            issue_started;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            issue_x          <= '0;
            issue_y          <= '0;
            issue_started    <= 1'b0;
            frame_start_pulse <= 1'b0;
            frame_done_pulse  <= 1'b0;
            for (int i = 0; i < LANES; i++) begin
                lane_px[i]       <= '0;
                lane_py[i]       <= '0;
                lane_in_valid[i] <= 1'b0;
            end
        end else begin
            frame_start_pulse <= 1'b0;
            frame_done_pulse  <= 1'b0;

            if (lane_phase[0] == FEED_PHASE[$clog2(FOLD)-1:0]) begin
                issue_started <= 1'b1;
                if ((issue_x == '0) && (issue_y == '0))
                    frame_start_pulse <= 1'b1;

                for (int i = 0; i < LANES; i++) begin
                    lane_px[i]       <= issue_x + PX_W'(i);
                    lane_py[i]       <= issue_y;
                    lane_in_valid[i] <= ((issue_x + i) < W);
                end

                if ((issue_x + LANES) >= W) begin
                    issue_x <= '0;
                    if (issue_y == H-1) begin
                        issue_y <= '0;
                        frame_done_pulse <= 1'b1;
                    end else begin
                        issue_y <= issue_y + 1'b1;
                    end
                end else begin
                    issue_x <= issue_x + PX_W'(LANES);
                end
            end else if (!issue_started) begin
                for (int i = 0; i < LANES; i++)
                    lane_in_valid[i] <= 1'b0;
            end
        end
    end

    logic [23:0]          buf_data [LANES];
    logic [PX_W-1:0]      buf_x    [LANES];
    logic [PY_W-1:0]      buf_y    [LANES];
    logic                 buf_user [LANES];
    logic                 buf_last [LANES];
    logic [$clog2(LANES):0] buf_count;
    logic [$clog2(LANES)-1:0] buf_rd_idx;
    logic [$clog2(LANES):0] lane_valid_count;

    wire any_lane_valid = lane_out_valid[0] | lane_out_valid[1] | lane_out_valid[2];
    wire axis_fire = m_axis_tvalid && m_axis_tready;

    assign m_axis_tvalid = (buf_count != '0);
    assign m_axis_tdata  = buf_data[buf_rd_idx];
    assign m_axis_tuser  = buf_user[buf_rd_idx];
    assign m_axis_tlast  = buf_last[buf_rd_idx];
    assign m_axis_x      = buf_x[buf_rd_idx];
    assign m_axis_y      = buf_y[buf_rd_idx];

    always_comb begin
        lane_valid_count = '0;
        for (int i = 0; i < LANES; i++) begin
            if (lane_out_valid[i])
                lane_valid_count = lane_valid_count + 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            buf_count        <= '0;
            buf_rd_idx       <= '0;
            reorder_overflow <= 1'b0;
            for (int i = 0; i < LANES; i++) begin
                buf_data[i] <= '0;
                buf_x[i]    <= '0;
                buf_y[i]    <= '0;
                buf_user[i] <= 1'b0;
                buf_last[i] <= 1'b0;
            end
        end else begin
            if (axis_fire) begin
                if (buf_count == 1) begin
                    buf_count  <= '0;
                    buf_rd_idx <= '0;
                end else begin
                    buf_count  <= buf_count - 1'b1;
                    buf_rd_idx <= buf_rd_idx + 1'b1;
                end
            end

            if (any_lane_valid) begin
                if ((buf_count != '0) && !(axis_fire && (buf_count == 1)))
                    reorder_overflow <= 1'b1;

                buf_rd_idx <= '0;
                buf_count  <= lane_valid_count;
                for (int i = 0; i < LANES; i++) begin
                    buf_data[i] <= {lane_r[i], lane_g[i], lane_b[i]};
                    buf_x[i]    <= lane_px_out[i];
                    buf_y[i]    <= lane_py_out[i];
                    buf_user[i] <= lane_out_valid[i] &&
                                   (lane_px_out[i] == '0) && (lane_py_out[i] == '0);
                    buf_last[i] <= lane_out_valid[i] && (lane_px_out[i] == W-1);
                end
            end
        end
    end

endmodule
