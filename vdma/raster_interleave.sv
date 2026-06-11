// ============================================================================
//  raster_interleave.sv  (3 parallel 1px/16cyc lanes -> raster pixel stream)
//  ----------------------------------------------------------------------------
//  Throughput: 3 lanes x 1px/16cyc @100MHz = 18.75 Mpix/s (~61 fps @640x480).
//
//  Column-class dispatch: lane L renders column (3k+L) of row y.  All three
//  lanes are fed the same triple on the same cycle (every 16 cycles), so their
//  identical-latency outputs emerge aligned.  An output gather then emits the
//  (up to) three results in column order 3k, 3k+1, 3k+2 -> naturally raster.
//  W=640 is not a multiple of 3, so the last triple of each row is partial;
//  out-of-range lanes are masked (valid_in low -> valid_out low -> skipped).
//
//  Heightmap: each lane owns 4 dual-port copies (heightmap_bram_dp128); 3 lanes
//  = 12 copies = 96 RAMB36 tiles, instantiated here so the top is clean.
//
//  Output is a simple ready/valid raster stream (rgb + px/py + sof/eol) for the
//  downstream packer / VDMA wrapper (built in the Vivado VDMA step).
//
//  Backpressure note: a new triple arrives every 16 cycles and the gather emits
//  <=3 pixels, so out_ready may stall up to ~13 cycles without loss.  Sustained
//  longer stalls need a deeper output FIFO (the VDMA side normally absorbs this).
// ============================================================================

module raster_interleave #(
    parameter int W        = 640,
    parameter int H        = 480,
    parameter int GRID_N   = 128,
    parameter int IDX_W    = $clog2(GRID_N),
    parameter int ADDR_W   = IDX_W*2,
    parameter int N_STEPS  = 32,
    parameter int N_PORTS  = 8,
    parameter int N_COPIES = N_PORTS/2,   // 4 dual-port copies per lane
    parameter int FOLD     = 16,
    parameter int H_W      = 16,
    parameter int H_I      = 2,
    parameter int DIR_W    = 16,
    parameter int POS_W    = 16,
    parameter int PX_W     = $clog2(W),
    parameter int PY_W     = $clog2(H),
    parameter int PHASE_W  = $clog2(FOLD)
)(
    input  logic                       clk,
    input  logic                       rst_n,
    input  logic                       en,

    // shared camera (broadcast to all lanes)
    input  logic signed [POS_W-1:0]    Ox, Oy, Oz,
    input  logic signed [DIR_W-1:0]    fwd_x, fwd_y, fwd_z,
    input  logic signed [DIR_W-1:0]    right_x, right_y, right_z,
    input  logic signed [DIR_W-1:0]    up_x, up_y, up_z,
    input  logic signed [DIR_W-1:0]    sun_dx, sun_dy, sun_dz,

    // raster-ordered output stream
    input  logic                       out_ready,
    output logic                       out_valid,
    output logic [7:0]                 out_r, out_g, out_b,
    output logic [PX_W-1:0]            out_px,
    output logic [PY_W-1:0]            out_py,
    output logic                       out_sof,    // start of frame
    output logic                       out_eol     // end of line
);

    // =================================================================
    //  Feeder: walk column triples (3k, 3k+1, 3k+2) x rows, 1 triple / FOLD.
    // =================================================================
    logic [PHASE_W-1:0] phase;
    logic [PX_W:0]      base_x;     // 0,3,...,<W
    logic [PY_W-1:0]    y;
    logic               fire;       // 1-cycle pulse at phase 0

    assign fire = (phase == '0);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            phase  <= '0;
            base_x <= '0;
            y      <= '0;
        end else if (en) begin
            phase <= (phase == FOLD-1) ? '0 : phase + 1'b1;
            if (fire) begin
                if (base_x + 3 >= W) begin
                    base_x <= '0;
                    y      <= (y == H-1) ? '0 : y + 1'b1;
                end else begin
                    base_x <= base_x + 3;
                end
            end
        end
    end

    // Per-lane feed
    logic [PX_W-1:0] lane_px   [3];
    logic            lane_vin  [3];
    always_comb begin
        for (int L = 0; L < 3; L++) begin
            lane_px[L]  = base_x[PX_W-1:0] + L[PX_W-1:0];
            lane_vin[L] = fire && ((base_x + L) < W);
        end
    end

    // =================================================================
    //  Three lanes + their heightmap copies.
    // =================================================================
    logic [7:0]      lr [3], lg [3], lb [3];
    logic [PX_W-1:0] lpx [3];
    logic [PY_W-1:0] lpy [3];
    logic            lvalid [3];

    genvar Lg, c;
    generate
        for (Lg = 0; Lg < 3; Lg++) begin : g_lane
            logic [ADDR_W-1:0]     baddr [N_PORTS];
            logic                  bre   [N_PORTS];
            logic signed [H_W-1:0] bdout [N_PORTS];

            // 4 dual-port copies: copy c serves ports {2c (A), 2c+1 (B)}.
            for (c = 0; c < N_COPIES; c++) begin : g_copy
                heightmap_bram_dp128 #(.ADDR_W(ADDR_W), .DATA_W(H_W)) u_hm (
                    .clk(clk),
                    .addr_a(baddr[2*c]),   .re_a(1'b1), .dout_a(bdout[2*c]),
                    .addr_b(baddr[2*c+1]), .re_b(1'b1), .dout_b(bdout[2*c+1])
                );
            end

            lane #(
                .W(W), .H(H), .GRID_N(GRID_N), .H_W(H_W), .H_I(H_I),
                .DIR_W(DIR_W), .POS_W(POS_W),
                .N_STEPS(N_STEPS), .N_PORTS(N_PORTS), .FOLD(FOLD),
                .PX_W(PX_W), .PY_W(PY_W)
            ) u_lane (
                .clk(clk), .rst_n(rst_n), .en(en),
                .Ox(Ox), .Oy(Oy), .Oz(Oz),
                .fwd_x(fwd_x), .fwd_y(fwd_y), .fwd_z(fwd_z),
                .right_x(right_x), .right_y(right_y), .right_z(right_z),
                .up_x(up_x), .up_y(up_y), .up_z(up_z),
                .sun_dx(sun_dx), .sun_dy(sun_dy), .sun_dz(sun_dz),
                .px_in(lane_px[Lg]), .py_in(y), .valid_in(lane_vin[Lg]),
                .bram_addr(baddr), .bram_re(bre), .bram_dout(bdout),
                .r_out(lr[Lg]), .g_out(lg[Lg]), .b_out(lb[Lg]),
                .px_out(lpx[Lg]), .py_out(lpy[Lg]), .valid_out(lvalid[Lg])
            );
        end
    endgenerate

    // =================================================================
    //  Output gather: lanes emit aligned; serialize the triple in column
    //  order (lane0, lane1, lane2), skipping masked lanes.
    // =================================================================
    logic            triple_fire;
    assign triple_fire = lvalid[0] | lvalid[1] | lvalid[2];

    logic [7:0]      sr [3], sg [3], sb [3];
    logic [PX_W-1:0] spx [3];
    logic [PY_W-1:0] spy [3];
    logic [2:0]      sv;
    logic [1:0]      emit_idx;        // 0..3 (3 = done)
    logic            busy;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            busy     <= 1'b0;
            emit_idx <= 2'd0;
            sv       <= 3'b0;
            out_valid<= 1'b0;
        end else if (en) begin
            // default: deassert valid when consumed
            if (out_valid && out_ready)
                out_valid <= 1'b0;

            if (!busy && triple_fire) begin
                // latch the aligned triple
                for (int L = 0; L < 3; L++) begin
                    sr[L]<=lr[L]; sg[L]<=lg[L]; sb[L]<=lb[L];
                    spx[L]<=lpx[L]; spy[L]<=lpy[L];
                end
                sv       <= {lvalid[2], lvalid[1], lvalid[0]};
                busy     <= 1'b1;
                emit_idx <= 2'd0;
            end else if (busy) begin
                // advance only when the current output slot is consumed (or empty)
                if (!out_valid || out_ready) begin
                    if (emit_idx == 2'd3) begin
                        busy <= 1'b0;
                    end else if (sv[emit_idx]) begin
                        out_r  <= sr[emit_idx];
                        out_g  <= sg[emit_idx];
                        out_b  <= sb[emit_idx];
                        out_px <= spx[emit_idx];
                        out_py <= spy[emit_idx];
                        out_valid <= 1'b1;
                        emit_idx  <= emit_idx + 2'd1;
                    end else begin
                        emit_idx  <= emit_idx + 2'd1;  // skip masked lane
                    end
                end
            end
        end
    end

    assign out_sof = (out_px == '0) && (out_py == '0);
    assign out_eol = (out_px == (W-1));

endmodule
