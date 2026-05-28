// ============================================================================
//  march_step3.sv  (Design 3: bilinear-in-marcher, half-rate, 2 ports/step)
//  ----------------------------------------------------------------------------
//  Same march algorithm as march_step2, but the height lookup inside every
//  step is now a TRUE BILINEAR interpolation of the 4 surrounding heightmap
//  corners, instead of a nearest-neighbour read.  The hit test compares the
//  ray's Pz against the bilinearly-interpolated surface height `h_interp`, so
//  hits land on the smooth surface and silhouettes are smooth (not blocky at
//  cell boundaries).
//
//  KEY DIFFERENCES vs march_step2
//  ------------------------------
//   1. 2 BRAM ports (was 1).  4 corner reads are spread 2+2 across two cycles
//      using the marcher's 1-bit phase:
//
//                       phase = 0              phase = 1
//          port 0       (ix0, iy0) = h00       (ix1, iy0) = h10
//          port 1       (ix0, iy1) = h01       (ix1, iy1) = h11
//
//      i.e. phase 0 reads the LEFT column, phase 1 reads the RIGHT column.
//      Each step OWNS its 2 ports (no sharing between steps in Design 3),
//      so MY_PHASE is GONE — every step simply reads both ports every cycle,
//      and `phase_in` only selects which x-column the addresses point at.
//
//   2. No port sharing  =>  no MY_PHASE parameter, no inter-step muxing.
//
//   3. 7 internal pipeline stages (was 5):
//          A   : advance position P += dt*D
//          B   : compute ix0/iy0/ix1/iy1, xf, yf; drive 2 ports for this phase
//          C   : capture first column  (h00,h01 if phase0 issued / h10,h11 if 1)
//          C2  : capture second column (the other half) -> all 4 corners held
//          D   : x-lerps  -> h_top, h_bot           (2 parallel multiplies)
//          D2  : y-lerp    -> h_interp, then below/cross compare
//          E   : phase-alignment / output buffer
//
//      The lerp is split across D and D2 (3 dependent multiplies would be a
//      ~3-deep multiplier chain in one stage -> timing risk at 100 MHz), the
//      same split normal2 uses in its stages 5/6.
//
//   4. The hit test, prev_below chain and h_hit all use h_interp (smooth),
//      not the nearest-neighbour height.
//
//  PRESERVED INVARIANTS
//  --------------------
//   - Frozen-ray pattern: once HIT/OFFGRID, ray passes through untouched.
//   - Bug 2 fix: step 0 cannot declare a HIT (step_count_C2 != 0 required);
//     it only establishes prev_below (now against h_interp).
//   - Fixed-point arithmetic + lerp truncation identical to normal2 so the
//     Python golden model can mirror it bit-for-bit (FRAC_W = 8).
//
//  Latency: 7 cycles.  Throughput when chained in marcher3: 1 pixel / 2 cyc.
// ============================================================================

module march_step3 #(
    // ----- Position fixed-point format -----
    parameter int POS_W      = 16,
    parameter int POS_I      = 4,
    parameter int POS_F      = POS_W - 1 - POS_I,

    // ----- Direction fixed-point format -----
    parameter int DIR_W      = 16,
    parameter int DIR_I      = 2,
    parameter int DIR_F      = DIR_W - 1 - DIR_I,

    // ----- Heightmap geometry -----
    parameter int GRID_N     = 256,
    parameter int IDX_W      = $clog2(GRID_N),

    // ----- Heightmap value format -----
    parameter int H_W        = 16,
    parameter int H_I        = 4,
    parameter int H_F        = H_W - 1 - H_I,

    // ----- Hit-distance proxy -----
    parameter int STEP_W     = 5,

    // ----- Bilinear fractional weight width (must match normal/golden) -----
    parameter int FRAC_W     = 8,

    // ----- World extents -----
    parameter logic signed [POS_W-1:0] WORLD_HALF = (1 <<< POS_F),

    // ----- Step size: dt = 2*WORLD_HALF / GRID_N  => one cell per step -----
    parameter logic signed [POS_W-1:0] DT = (2 * WORLD_HALF) / GRID_N
)(
    input  logic                       clk,
    input  logic                       rst_n,
    input  logic                       en,           // ~stall
    input  logic                       phase_in,     // toggles every cycle (from marcher3)

    // ----- Pipeline data in -----
    input  logic signed [POS_W-1:0]    Px_in,
    input  logic signed [POS_W-1:0]    Py_in,
    input  logic signed [POS_W-1:0]    Pz_in,
    input  logic signed [DIR_W-1:0]    Dx,
    input  logic signed [DIR_W-1:0]    Dy,
    input  logic signed [DIR_W-1:0]    Dz,
    input  logic [1:0]                 status_in,    // 00=MARCHING 01=HIT 10=OFF
    input  logic                       prev_below_in,
    input  logic signed [H_W-1:0]      h_hit_in,
    input  logic [IDX_W-1:0]           ix_hit_in,
    input  logic [IDX_W-1:0]           iy_hit_in,
    input  logic signed [POS_W-1:0]    Px_hit_in,
    input  logic signed [POS_W-1:0]    Py_hit_in,
    input  logic [STEP_W-1:0]          step_count_in,
    input  logic                       valid_in,

    // ----- 2 BRAM read ports (issued in stage B, returned C/C2) -----
    //   port 0 : phase0 -> h00 (ix0,iy0)   phase1 -> h10 (ix1,iy0)
    //   port 1 : phase0 -> h01 (ix0,iy1)   phase1 -> h11 (ix1,iy1)
    output logic [IDX_W*2-1:0]         bram_addr [2],
    output logic                       bram_re   [2],
    input  logic signed [H_W-1:0]      bram_dout [2],

    // ----- Pipeline data out -----
    output logic signed [POS_W-1:0]    Px_out,
    output logic signed [POS_W-1:0]    Py_out,
    output logic signed [POS_W-1:0]    Pz_out,
    output logic signed [DIR_W-1:0]    Dx_out,
    output logic signed [DIR_W-1:0]    Dy_out,
    output logic signed [DIR_W-1:0]    Dz_out,
    output logic [1:0]                 status_out,
    output logic                       prev_below_out,
    output logic signed [H_W-1:0]      h_hit_out,
    output logic [IDX_W-1:0]           ix_hit_out,
    output logic [IDX_W-1:0]           iy_hit_out,
    output logic signed [POS_W-1:0]    Px_hit_out,
    output logic signed [POS_W-1:0]    Py_hit_out,
    output logic [STEP_W-1:0]          step_count_out,
    output logic                       valid_out
);

    localparam logic [1:0] ST_MARCHING = 2'b00;
    localparam logic [1:0] ST_HIT      = 2'b01;
    localparam logic [1:0] ST_OFFGRID  = 2'b10;


    // =================================================================
    //  STAGE A: advance position.  P_new = P_in + dt*D  (if MARCHING).
    //  Frozen rays pass through unchanged.  Identical to march_step2.
    // =================================================================
    logic signed [POS_W + DIR_W - 1 : 0]  raw_dtDx, raw_dtDy, raw_dtDz;
    logic signed [POS_W - 1 : 0]          inc_Px, inc_Py, inc_Pz;

    always_comb begin
        raw_dtDx = $signed(DT) * Dx;
        raw_dtDy = $signed(DT) * Dy;
        raw_dtDz = $signed(DT) * Dz;
        inc_Px = raw_dtDx[DIR_F + POS_W - 1 -: POS_W];
        inc_Py = raw_dtDy[DIR_F + POS_W - 1 -: POS_W];
        inc_Pz = raw_dtDz[DIR_F + POS_W - 1 -: POS_W];
    end

    logic signed [POS_W-1:0]   Px_A, Py_A, Pz_A;
    logic signed [DIR_W-1:0]   Dx_A, Dy_A, Dz_A;
    logic [1:0]                stat_A;
    logic                      prev_A;
    logic signed [H_W-1:0]     h_hit_A;
    logic [IDX_W-1:0]          ix_hit_A, iy_hit_A;
    logic signed [POS_W-1:0]   Px_hit_A, Py_hit_A;
    logic [STEP_W-1:0]         step_count_A;
    logic                      v_A;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            v_A <= 1'b0;
        end else if (en) begin
            if (status_in == ST_MARCHING) begin
                Px_A <= Px_in + inc_Px;
                Py_A <= Py_in + inc_Py;
                Pz_A <= Pz_in + inc_Pz;
            end else begin
                Px_A <= Px_in;
                Py_A <= Py_in;
                Pz_A <= Pz_in;
            end
            Dx_A         <= Dx;
            Dy_A         <= Dy;
            Dz_A         <= Dz;
            stat_A       <= status_in;
            prev_A       <= prev_below_in;
            h_hit_A      <= h_hit_in;
            ix_hit_A     <= ix_hit_in;
            iy_hit_A     <= iy_hit_in;
            Px_hit_A     <= Px_hit_in;
            Py_hit_A     <= Py_hit_in;
            step_count_A <= step_count_in;
            v_A          <= valid_in;
        end
    end


    // =================================================================
    //  STAGE B: world position -> floor cell (ix0,iy0), neighbour cells
    //  (ix1,iy1), fractional weights (xf,yf).  Off-grid test on the floor
    //  cell.  Drive the 2 BRAM ports for this phase's column.
    //
    //  Arithmetic mirrors march_step2 (index) + normal2 (frac) exactly.
    // =================================================================
    localparam int W2G_SHIFT = POS_F + 1 - $clog2(GRID_N);

    logic signed [POS_W:0]  ix_raw, iy_raw;
    logic                   offgrid_B;
    logic [IDX_W-1:0]       ix0_B, iy0_B;
    logic [IDX_W-1:0]       ix1_B, iy1_B;

    // Fractional parts (reuse normal2's extraction)
    logic [POS_W:0]         Px_shifted, Py_shifted;
    logic [FRAC_W-1:0]      xf_B, yf_B;

    always_comb begin
        ix_raw = $signed({Px_A[POS_W-1], Px_A}) + $signed({1'b0, WORLD_HALF});
        iy_raw = $signed({Py_A[POS_W-1], Py_A}) + $signed({1'b0, WORLD_HALF});
        ix_raw = ix_raw >>> W2G_SHIFT;
        iy_raw = iy_raw >>> W2G_SHIFT;
        offgrid_B = (ix_raw < 0) || (ix_raw >= GRID_N) ||
                    (iy_raw < 0) || (iy_raw >= GRID_N);

        Px_shifted = $signed({Px_A[POS_W-1], Px_A}) + $signed({1'b0, WORLD_HALF});
        Py_shifted = $signed({Py_A[POS_W-1], Py_A}) + $signed({1'b0, WORLD_HALF});
    end

    assign ix0_B = ix_raw[IDX_W-1:0];
    assign iy0_B = iy_raw[IDX_W-1:0];
    assign ix1_B = (ix0_B == GRID_N-1) ? ix0_B : (ix0_B + 1'b1);
    assign iy1_B = (iy0_B == GRID_N-1) ? iy0_B : (iy0_B + 1'b1);

    generate
        if (W2G_SHIFT >= FRAC_W) begin : g_frac_narrow
            assign xf_B = Px_shifted[W2G_SHIFT-1 -: FRAC_W];
            assign yf_B = Py_shifted[W2G_SHIFT-1 -: FRAC_W];
        end else begin : g_frac_pad
            assign xf_B = { Px_shifted[W2G_SHIFT-1:0], {(FRAC_W - W2G_SHIFT){1'b0}} };
            assign yf_B = { Py_shifted[W2G_SHIFT-1:0], {(FRAC_W - W2G_SHIFT){1'b0}} };
        end
    endgenerate

    // BRAM addresses (combinational, like march_step2 stage B).
    //   phase 0 -> x = ix0  (LEFT column : h00,h01)
    //   phase 1 -> x = ix1  (RIGHT column: h10,h11)
    assign bram_addr[0] = (phase_in == 1'b0) ? {iy0_B, ix0_B}    // h00
                                             : {iy0_B, ix1_B};   // h10
    assign bram_addr[1] = (phase_in == 1'b0) ? {iy1_B, ix0_B}    // h01
                                             : {iy1_B, ix1_B};   // h11
    // No MY_PHASE gating: each step owns its 2 ports and reads every cycle
    // while marching on-grid.
    assign bram_re[0] = v_A && (stat_A == ST_MARCHING) && !offgrid_B;
    assign bram_re[1] = v_A && (stat_A == ST_MARCHING) && !offgrid_B;

    logic signed [POS_W-1:0]  Px_B, Py_B, Pz_B;
    logic signed [DIR_W-1:0]  Dx_B, Dy_B, Dz_B;
    logic [1:0]               stat_B;
    logic                     prev_B;
    logic signed [H_W-1:0]    h_hit_B;
    logic [IDX_W-1:0]         ix_hit_B, iy_hit_B;
    logic signed [POS_W-1:0]  Px_hit_B, Py_hit_B;
    logic [STEP_W-1:0]        step_count_B;
    logic                     v_B;
    logic [FRAC_W-1:0]        xf_Bq, yf_Bq;     // registered frac weights
    logic                     phase_B;          // phase that issued stage-B reads

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            v_B <= 1'b0;
        end else if (en) begin
            Px_B   <= Px_A;
            Py_B   <= Py_A;
            Pz_B   <= Pz_A;
            Dx_B   <= Dx_A;
            Dy_B   <= Dy_A;
            Dz_B   <= Dz_A;
            prev_B <= prev_A;
            v_B    <= v_A;
            xf_Bq  <= xf_B;
            yf_Bq  <= yf_B;
            phase_B <= phase_in;

            if (stat_A != ST_MARCHING)
                stat_B <= stat_A;
            else if (offgrid_B)
                stat_B <= ST_OFFGRID;
            else
                stat_B <= ST_MARCHING;

            // Capture the floor indices / world pos we just queried
            if (stat_A == ST_MARCHING && !offgrid_B) begin
                ix_hit_B <= ix0_B;
                iy_hit_B <= iy0_B;
                Px_hit_B <= Px_A;
                Py_hit_B <= Py_A;
            end else begin
                ix_hit_B <= ix_hit_A;
                iy_hit_B <= iy_hit_A;
                Px_hit_B <= Px_hit_A;
                Py_hit_B <= Py_hit_A;
            end

            h_hit_B <= h_hit_A;

            if (stat_A == ST_MARCHING)
                step_count_B <= step_count_A + 1'b1;
            else
                step_count_B <= step_count_A;
        end
    end


    // =================================================================
    //  STAGE C: first column of BRAM data arrives.
    //  The read issued in stage B at phase_B.  After 1 BRAM cycle the data
    //  on the ports corresponds to phase_B's column:
    //      phase_B==0 -> (h00,h01)   phase_B==1 -> (h10,h11)
    //  Capture into the matching corner regs; hold the others.
    // =================================================================
    logic signed [POS_W-1:0]  Px_C, Py_C, Pz_C;
    logic signed [DIR_W-1:0]  Dx_C, Dy_C, Dz_C;
    logic [1:0]               stat_C;
    logic                     prev_C;
    logic signed [H_W-1:0]    h_hit_C;
    logic [IDX_W-1:0]         ix_hit_C, iy_hit_C;
    logic signed [POS_W-1:0]  Px_hit_C, Py_hit_C;
    logic [STEP_W-1:0]        step_count_C;
    logic                     v_C;
    logic [FRAC_W-1:0]        xf_C, yf_C;
    logic                     phase_C;
    logic signed [H_W-1:0]    h00_C, h10_C, h01_C, h11_C;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            v_C <= 1'b0;
        end else if (en) begin
            Px_C         <= Px_B;
            Py_C         <= Py_B;
            Pz_C         <= Pz_B;
            Dx_C         <= Dx_B;
            Dy_C         <= Dy_B;
            Dz_C         <= Dz_B;
            stat_C       <= stat_B;
            prev_C       <= prev_B;
            h_hit_C      <= h_hit_B;
            ix_hit_C     <= ix_hit_B;
            iy_hit_C     <= iy_hit_B;
            Px_hit_C     <= Px_hit_B;
            Py_hit_C     <= Py_hit_B;
            step_count_C <= step_count_B;
            v_C          <= v_B;
            xf_C         <= xf_Bq;
            yf_C         <= yf_Bq;
            phase_C      <= phase_B;

            // First-column capture, keyed on the phase that issued the read.
            if (phase_B == 1'b0) begin
                h00_C <= bram_dout[0];
                h01_C <= bram_dout[1];
            end else begin
                h10_C <= bram_dout[0];
                h11_C <= bram_dout[1];
            end
        end
    end


    // =================================================================
    //  STAGE C2: second column of BRAM data arrives (the opposite phase's
    //  column, one cycle later).  After this stage all 4 corners are held.
    // =================================================================
    logic signed [POS_W-1:0]  Px_C2, Py_C2, Pz_C2;
    logic signed [DIR_W-1:0]  Dx_C2, Dy_C2, Dz_C2;
    logic [1:0]               stat_C2;
    logic                     prev_C2;
    logic signed [H_W-1:0]    h_hit_C2;
    logic [IDX_W-1:0]         ix_hit_C2, iy_hit_C2;
    logic signed [POS_W-1:0]  Px_hit_C2, Py_hit_C2;
    logic [STEP_W-1:0]        step_count_C2;
    logic                     v_C2;
    logic [FRAC_W-1:0]        xf_C2, yf_C2;
    logic signed [H_W-1:0]    h00_C2, h10_C2, h01_C2, h11_C2;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            v_C2 <= 1'b0;
        end else if (en) begin
            Px_C2         <= Px_C;
            Py_C2         <= Py_C;
            Pz_C2         <= Pz_C;
            Dx_C2         <= Dx_C;
            Dy_C2         <= Dy_C;
            Dz_C2         <= Dz_C;
            stat_C2       <= stat_C;
            prev_C2       <= prev_C;
            h_hit_C2      <= h_hit_C;
            ix_hit_C2     <= ix_hit_C;
            iy_hit_C2     <= iy_hit_C;
            Px_hit_C2     <= Px_hit_C;
            Py_hit_C2     <= Py_hit_C;
            step_count_C2 <= step_count_C;
            v_C2          <= v_C;
            xf_C2         <= xf_C;
            yf_C2         <= yf_C;

            // Carry the already-captured (first) column forward
            h00_C2 <= h00_C;
            h10_C2 <= h10_C;
            h01_C2 <= h01_C;
            h11_C2 <= h11_C;

            // Second column is the OTHER phase's data, on the ports this cycle.
            // First read was phase_C; the second-half data here is ~phase_C.
            if (phase_C == 1'b0) begin
                // first half was h00/h01 -> now capture h10/h11
                h10_C2 <= bram_dout[0];
                h11_C2 <= bram_dout[1];
            end else begin
                // first half was h10/h11 -> now capture h00/h01
                h00_C2 <= bram_dout[0];
                h01_C2 <= bram_dout[1];
            end
        end
    end


    // =================================================================
    //  STAGE D: x-direction lerps.  Two PARALLEL multiplies.
    //      h_top = h00 + (h10 - h00) * xf      (low-y edge)
    //      h_bot = h01 + (h11 - h01) * xf      (high-y edge)
    //  Arithmetic identical to normal2 stage 5.
    // =================================================================
    logic signed [H_W:0]            diff_top_comb, diff_bot_comb;
    logic signed [H_W+FRAC_W:0]     prod_top_comb, prod_bot_comb;
    logic signed [H_W-1:0]          h_top_comb, h_bot_comb;

    always_comb begin
        diff_top_comb = $signed(h10_C2) - $signed(h00_C2);
        diff_bot_comb = $signed(h11_C2) - $signed(h01_C2);
        prod_top_comb = diff_top_comb * $signed({1'b0, xf_C2});
        prod_bot_comb = diff_bot_comb * $signed({1'b0, xf_C2});
        h_top_comb = $signed(h00_C2) + prod_top_comb[H_W+FRAC_W-1 -: H_W];
        h_bot_comb = $signed(h01_C2) + prod_bot_comb[H_W+FRAC_W-1 -: H_W];
    end

    logic signed [POS_W-1:0]  Px_D, Py_D, Pz_D;
    logic signed [DIR_W-1:0]  Dx_D, Dy_D, Dz_D;
    logic [1:0]               stat_D;
    logic                     prev_D;
    logic signed [H_W-1:0]    h_hit_D;
    logic [IDX_W-1:0]         ix_hit_D, iy_hit_D;
    logic signed [POS_W-1:0]  Px_hit_D, Py_hit_D;
    logic [STEP_W-1:0]        step_count_D;
    logic                     v_D;
    logic [FRAC_W-1:0]        yf_D;
    logic signed [H_W-1:0]    h_top_D, h_bot_D;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            v_D <= 1'b0;
        end else if (en) begin
            Px_D         <= Px_C2;
            Py_D         <= Py_C2;
            Pz_D         <= Pz_C2;
            Dx_D         <= Dx_C2;
            Dy_D         <= Dy_C2;
            Dz_D         <= Dz_C2;
            stat_D       <= stat_C2;
            prev_D       <= prev_C2;
            h_hit_D      <= h_hit_C2;
            ix_hit_D     <= ix_hit_C2;
            iy_hit_D     <= iy_hit_C2;
            Px_hit_D     <= Px_hit_C2;
            Py_hit_D     <= Py_hit_C2;
            step_count_D <= step_count_C2;
            v_D          <= v_C2;
            yf_D         <= yf_C2;

            h_top_D <= h_top_comb;
            h_bot_D <= h_bot_comb;
        end
    end


    // =================================================================
    //  STAGE D2: y-direction lerp + hit test.
    //      h_interp = h_top + (h_bot - h_top) * yf
    //  Then compare Pz vs h_interp, detect surface crossing, update status.
    //  Bug 2 fix preserved (step_count != 0 required for a HIT).
    // =================================================================
    localparam int H_ALIGN_SHIFT = POS_F - H_F;

    logic signed [H_W:0]          diff_y_comb;
    logic signed [H_W+FRAC_W:0]   prod_y_comb;
    logic signed [H_W-1:0]        h_interp_comb;
    logic signed [POS_W-1:0]      h_aligned;
    logic                         below_D2;
    logic                         crossed_D2;

    always_comb begin
        diff_y_comb   = $signed(h_bot_D) - $signed(h_top_D);
        prod_y_comb   = diff_y_comb * $signed({1'b0, yf_D});
        h_interp_comb = $signed(h_top_D) + prod_y_comb[H_W+FRAC_W-1 -: H_W];

        h_aligned = $signed(h_interp_comb) <<< H_ALIGN_SHIFT;
        below_D2  = (Pz_D < h_aligned);
        crossed_D2 = (stat_D == ST_MARCHING)
                  && (below_D2 != prev_D)
                  && (step_count_D != '0);   // Bug 2 fix
    end

    logic signed [POS_W-1:0]  Px_D2, Py_D2, Pz_D2;
    logic signed [DIR_W-1:0]  Dx_D2, Dy_D2, Dz_D2;
    logic [1:0]               stat_D2;
    logic                     prev_D2;
    logic signed [H_W-1:0]    h_hit_D2;
    logic [IDX_W-1:0]         ix_hit_D2, iy_hit_D2;
    logic signed [POS_W-1:0]  Px_hit_D2, Py_hit_D2;
    logic [STEP_W-1:0]        step_count_D2;
    logic                     v_D2;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            v_D2 <= 1'b0;
        end else if (en) begin
            Px_D2         <= Px_D;
            Py_D2         <= Py_D;
            Pz_D2         <= Pz_D;
            Dx_D2         <= Dx_D;
            Dy_D2         <= Dy_D;
            Dz_D2         <= Dz_D;
            step_count_D2 <= step_count_D;
            v_D2          <= v_D;

            if (stat_D == ST_MARCHING && crossed_D2) begin
                stat_D2   <= ST_HIT;
                h_hit_D2  <= h_interp_comb;   // smooth surface height at hit
                ix_hit_D2 <= ix_hit_D;
                iy_hit_D2 <= iy_hit_D;
                Px_hit_D2 <= Px_hit_D;
                Py_hit_D2 <= Py_hit_D;
            end else begin
                stat_D2   <= stat_D;
                h_hit_D2  <= h_hit_D;
                ix_hit_D2 <= ix_hit_D;
                iy_hit_D2 <= iy_hit_D;
                Px_hit_D2 <= Px_hit_D;
                Py_hit_D2 <= Py_hit_D;
            end

            // prev_below now tracks the interpolated-surface comparison
            if (stat_D == ST_MARCHING)
                prev_D2 <= below_D2;
            else
                prev_D2 <= prev_D;
        end
    end


    // =================================================================
    //  STAGE E: phase-alignment / output buffer.  Pure passthrough.
    //  7 stages total is odd, so adjacent steps in the chain land on
    //  opposite phases (harmless in Design 3 since ports aren't shared).
    // =================================================================
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
        end else if (en) begin
            Px_out         <= Px_D2;
            Py_out         <= Py_D2;
            Pz_out         <= Pz_D2;
            Dx_out         <= Dx_D2;
            Dy_out         <= Dy_D2;
            Dz_out         <= Dz_D2;
            status_out     <= stat_D2;
            prev_below_out <= prev_D2;
            h_hit_out      <= h_hit_D2;
            ix_hit_out     <= ix_hit_D2;
            iy_hit_out     <= iy_hit_D2;
            Px_hit_out     <= Px_hit_D2;
            Py_hit_out     <= Py_hit_D2;
            step_count_out <= step_count_D2;
            valid_out      <= v_D2;
        end
    end

endmodule
