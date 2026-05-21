// ============================================================================
//  march_step.sv
//  ----------------------------------------------------------------------------
//  One iteration of the heightmap ray-march.
//
//  Each step advances the ray by `dt`, looks up the terrain height at the
//  new (x, y), and decides one of three things:
//      * the ray is still marching                          (status = MARCHING)
//      * the ray just crossed the terrain surface           (status = HIT)
//      * the ray walked off the heightmap                   (status = OFF_GRID)
//
//  Once a ray is HIT or OFF_GRID, all downstream march_step instances
//  pass it through unchanged: the "frozen ray" pattern.
//
//  Internal pipeline:
//      Stage A:  P_new = P_in + dt*D     (advance the ray)
//      Stage B:  compute (ix, iy), issue BRAM read, off-grid check
//      Stage C:  receive BRAM data (1-cycle BRAM read latency)
//      Stage D:  compare P_new.z to h, detect sign change, update status
//
//  Total: 4 cycles latency per step.
//
//  Convention: z is height, (x, y) are horizontal heightmap coordinates.
// ============================================================================

module march_step #(
    // ----- Position fixed-point format -----
    parameter int POS_W      = 16,
    parameter int POS_I      = 4,                  // integer bits (+1 sign)
    parameter int POS_F      = POS_W - 1 - POS_I,  // = 11

    // ----- Direction fixed-point format -----
    parameter int DIR_W      = 16,
    parameter int DIR_I      = 2,
    parameter int DIR_F      = DIR_W - 1 - DIR_I,  // = 13

    // ----- Heightmap geometry -----
    parameter int GRID_N     = 256,                // heightmap is GRID_N x GRID_N
    parameter int IDX_W      = $clog2(GRID_N),     // bits to index one axis

    // ----- Heightmap value format -----
    parameter int H_W        = 16,
    parameter int H_I        = 4,
    parameter int H_F        = H_W - 1 - H_I,

    // ----- Hit-distance proxy -----
    parameter int STEP_W     = 5,

    // ----- World extents -----
    // World x in [-WORLD_HALF, +WORLD_HALF].  Heightmap covers the same.
    parameter logic signed [POS_W-1:0] WORLD_HALF =
        (1 <<< POS_F),                              // = 1.0 in Q-format

    // ----- Step size dt (constant per design) -----
    // dt is in the same units as t and P.  Pick so that ~one heightmap cell
    // width per step.  cell = 2*WORLD_HALF / GRID_N.
    parameter logic signed [POS_W-1:0] DT =
        (2 * WORLD_HALF) / GRID_N
)(
    input  logic                       clk,
    input  logic                       rst_n,
    input  logic                       en,           // pipeline-enable (~stall)

    // ----- Pipeline data in -----
    input  logic signed [POS_W-1:0]    Px_in,
    input  logic signed [POS_W-1:0]    Py_in,
    input  logic signed [POS_W-1:0]    Pz_in,
    input  logic signed [DIR_W-1:0]    Dx,
    input  logic signed [DIR_W-1:0]    Dy,
    input  logic signed [DIR_W-1:0]    Dz,
    input  logic [1:0]                 status_in,    // 00=MARCHING,01=HIT,10=OFF
    input  logic                       prev_below_in,
    input  logic signed [H_W-1:0]      h_hit_in,
    input  logic [IDX_W-1:0]           ix_hit_in,
    input  logic [IDX_W-1:0]           iy_hit_in,
    input  logic [STEP_W-1:0]          step_count_in,
    input  logic                       valid_in,

    // ----- BRAM read port (issued in stage B, returned in stage C) -----
    output logic [IDX_W*2-1:0]         bram_addr,    // {iy, ix}
    output logic                       bram_re,
    input  logic signed [H_W-1:0]      bram_dout,

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
    output logic [STEP_W-1:0]          step_count_out,
    output logic                       valid_out
);

    localparam logic [1:0] ST_MARCHING = 2'b00;
    localparam logic [1:0] ST_HIT      = 2'b01;
    localparam logic [1:0] ST_OFFGRID  = 2'b10;

    // =================================================================
    //  STAGE A -- advance the ray position:  P_new = P_in + dt*D
    //
    //  dt is a constant; dt*D is therefore three constant-multiplies
    //  (cheap) followed by three adds.  In practice the synthesiser
    //  collapses dt*D into a small shift/add network.
    // =================================================================
    // Pre-compute dt*D step.  Result aligned to POS_F.
    //   dt is Q(POS_I).(POS_F).  D is Q(DIR_I).(DIR_F).
    //   Product is Q(POS_I+DIR_I).(POS_F+DIR_F), then shifted right
    //   by DIR_F to land back in POS format.
    localparam int RAW_W   = POS_W + DIR_W;
    localparam int RAW_SHF = DIR_F;

    function automatic logic signed [POS_W-1:0] dt_times (
        input logic signed [DIR_W-1:0] d
    );
        logic signed [RAW_W-1:0] raw;
        raw = $signed(DT) * d;
        return raw[RAW_SHF + POS_W - 1 -: POS_W];
    endfunction

    // Stage A registers
    logic signed [POS_W-1:0]   PxA, PyA, PzA;
    logic signed [DIR_W-1:0]   DxA, DyA, DzA;
    logic [1:0]                statA;
    logic                      prevA;
    logic signed [H_W-1:0]     hHitA;
    logic [IDX_W-1:0]          ixHitA, iyHitA;
    logic [STEP_W-1:0]         stepCountA;
    logic                      vA;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            vA <= 1'b0;
        end else if (en) begin
            if (status_in == ST_MARCHING) begin
                PxA <= Px_in + dt_times(Dx);
                PyA <= Py_in + dt_times(Dy);
                PzA <= Pz_in + dt_times(Dz);
            end else begin
                // Frozen ray - just pass through
                PxA <= Px_in;
                PyA <= Py_in;
                PzA <= Pz_in;
            end
            DxA    <= Dx;
            DyA    <= Dy;
            DzA    <= Dz;
            statA  <= status_in;
            prevA  <= prev_below_in;
            hHitA  <= h_hit_in;
            ixHitA <= ix_hit_in;
            iyHitA <= iy_hit_in;
            stepCountA <= step_count_in;
            vA     <= valid_in;
        end
    end

    // =================================================================
    //  STAGE B -- compute heightmap indices, issue BRAM read,
    //             check for off-grid.
    //
    //  ix = floor( (Px + WORLD_HALF) * (GRID_N / (2*WORLD_HALF)) )
    //
    //  In our convention WORLD_HALF = 1.0 and GRID_N = 256, so
    //     ix = floor( (Px + 1.0) * 128 ).
    //
    //  Because Px is fixed-point Q(POS_I).(POS_F), this collapses to
    //  taking the relevant bit-slice -- no multiplier needed.
    // =================================================================

    // ix = (Px + WORLD_HALF) shifted to land the GRID_N range in the
    // integer part.  Compute it as an integer index of bit-width IDX_W+1
    // so we can detect overflow.
    function automatic logic signed [POS_W:0] world_to_grid (
        input logic signed [POS_W-1:0] p
    );
        // Add WORLD_HALF so 0..2*WORLD_HALF maps to 0..GRID_N range,
        // then shift to make the integer part the cell index.
        // ratio = GRID_N / (2*WORLD_HALF)
        //   POS_F bits of fraction; cell size is 2*WORLD_HALF/GRID_N
        //   in POS_F bits.  Equivalently, shift right by (POS_F - log2(GRID_N/2)).
        logic signed [POS_W:0] sum;
        sum = $signed({p[POS_W-1], p}) + $signed({1'b0, WORLD_HALF});
        return sum >>> (POS_F - $clog2(GRID_N) + $clog2(2));
    endfunction

    logic signed [POS_W:0] ix_raw, iy_raw;
    logic                  offgrid_B;
    logic [IDX_W-1:0]      ix_B, iy_B;

    // Stage B registers
    logic signed [POS_W-1:0]  PxB, PyB, PzB;
    logic signed [DIR_W-1:0]  DxB, DyB, DzB;
    logic [1:0]               statB;
    logic                     prevB;
    logic signed [H_W-1:0]    hHitB;
    logic [IDX_W-1:0]         ixHitB, iyHitB;
    logic [STEP_W-1:0]        stepCountB;
    logic                     vB;

    always_comb begin
        ix_raw    = world_to_grid(PxA);
        iy_raw    = world_to_grid(PyA);
        offgrid_B = (ix_raw < 0) || (ix_raw >= GRID_N) ||
                    (iy_raw < 0) || (iy_raw >= GRID_N);
        ix_B      = ix_raw[IDX_W-1:0];
        iy_B      = iy_raw[IDX_W-1:0];
    end

    // BRAM address output is combinational (registered inside the BRAM)
    assign bram_addr = {iy_B, ix_B};
    assign bram_re   = vA && (statA == ST_MARCHING) && !offgrid_B;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            vB <= 1'b0;
        end else if (en) begin
            PxB    <= PxA;
            PyB    <= PyA;
            PzB    <= PzA;
            DxB    <= DxA;
            DyB    <= DyA;
            DzB    <= DzA;
            prevB  <= prevA;
            hHitB  <= hHitA;
            ixHitB <= ixHitA;
            iyHitB <= iyHitA;
            stepCountB <= stepCountA;

            // Compute the new status for this stage:
            //   If we were already non-MARCHING, keep that status.
            //   If we just walked off the grid, switch to OFF_GRID.
            //   Otherwise stay MARCHING.
            if (statA != ST_MARCHING)
                statB <= statA;
            else if (offgrid_B)
                statB <= ST_OFFGRID;
            else
                statB <= ST_MARCHING;

            // Capture the indices we issued the read at, so stage D can
            // record them as the hit location.
            ixHitB <= (statA == ST_MARCHING && !offgrid_B) ? ix_B : ixHitA;
            iyHitB <= (statA == ST_MARCHING && !offgrid_B) ? iy_B : iyHitA;
            stepCountB <= (statA == ST_MARCHING) ? (stepCountA + 1'b1) : stepCountA;

            vB <= vA;
        end
    end

    // =================================================================
    //  STAGE C -- BRAM read latency.  Just forward everything one cycle.
    // =================================================================
    logic signed [POS_W-1:0]  PxC, PyC, PzC;
    logic signed [DIR_W-1:0]  DxC, DyC, DzC;
    logic [1:0]               statC;
    logic                     prevC;
    logic signed [H_W-1:0]    hHitC;
    logic [IDX_W-1:0]         ixHitC, iyHitC;
    logic [STEP_W-1:0]        stepCountC;
    logic                     vC;
    logic signed [H_W-1:0]    h_C;     // BRAM data when it arrives

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            vC <= 1'b0;
        end else if (en) begin
            PxC    <= PxB;
            PyC    <= PyB;
            PzC    <= PzB;
            DxC    <= DxB;
            DyC    <= DyB;
            DzC    <= DzB;
            statC  <= statB;
            prevC  <= prevB;
            hHitC  <= hHitB;
            ixHitC <= ixHitB;
            iyHitC <= iyHitB;
            stepCountC <= stepCountB;
            h_C    <= bram_dout;        // BRAM result arrives this cycle
            vC     <= vB;
        end
    end

    // =================================================================
    //  STAGE D -- compare Pz vs h, detect surface crossing, update status.
    //
    //  Pz is Q(POS_I).(POS_F).  h is Q(H_I).(H_F).  We need them in the
    //  same format to compare.  Align by shifting (assume H_F <= POS_F).
    // =================================================================
    // Align h into Pz's format.
    localparam int H_ALIGN_SHIFT = POS_F - H_F;     // assumed >= 0

    logic signed [POS_W-1:0]  h_aligned_D;
    logic                     below_D;
    logic                     crossed_D;

    always_comb begin
        // Sign-extend then shift left to put h into Pz's Q-format.
        h_aligned_D = $signed(h_C) <<< H_ALIGN_SHIFT;
        below_D     = (PzC < h_aligned_D);
        // Surface crossing detected only when actively marching.
        crossed_D   = (statC == ST_MARCHING) && (below_D != prevC);
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
        end else if (en) begin
            Px_out   <= PxC;
            Py_out   <= PyC;
            Pz_out   <= PzC;
            Dx_out   <= DxC;
            Dy_out   <= DyC;
            Dz_out   <= DzC;

            if (statC == ST_MARCHING && crossed_D) begin
                status_out  <= ST_HIT;
                h_hit_out   <= h_C;
                ix_hit_out  <= ixHitC;
                iy_hit_out  <= iyHitC;
            end else begin
                status_out  <= statC;
                h_hit_out   <= hHitC;
                ix_hit_out  <= ixHitC;
                iy_hit_out  <= iyHitC;
            end

            step_count_out <= stepCountC;
            prev_below_out <= (statC == ST_MARCHING) ? below_D : prevC;
            valid_out      <= vC;
        end
    end

endmodule
