// ============================================================================
//  normal.sv  (rewritten — clean, readable, no helper functions)
//  ----------------------------------------------------------------------------
//  Computes the surface normal at a HIT pixel by reading 4 neighbouring
//  heightmap cells and taking central differences.
//
//      Nx = -(h[ix+1,iy] - h[ix-1,iy])      tilted west if terrain rises east
//      Ny = -(h[ix,iy+1] - h[ix,iy-1])      tilted south if terrain rises north
//      Nz = +1.0                            constant (heightmap surface)
//
//  4 BRAM read ports.  Synchronous BRAM (1-cycle read latency).
//
//  Pipeline (4 stages, latency = 4 cycles):
//      Stage 1: latch inputs, compute clamped neighbour indices,
//               drive BRAM addresses (combinational from stage-1 regs).
//      Stage 2: BRAM is performing the read.
//               Stage-2 registers hold the pipeline payload but NOT BRAM data.
//      Stage 3: BRAM data is now valid on bram_dout[].
//               Latch the 4 heights into stage-3 registers.
//      Stage 4: compute dx_h, dy_h, Nx, Ny.  Register final outputs.
//
//  Total latency: 4 cycles.
//
//  For MISS / OFFGRID pixels: BRAM is still read (wasteful but harmless),
//  the shader discards the result by checking status.
// ============================================================================

module normal #(
    parameter int GRID_N     = 256,
    parameter int IDX_W      = $clog2(GRID_N),

    parameter int H_W        = 16,
    parameter int H_I        = 4,
    parameter int H_F        = H_W - 1 - H_I,

    parameter int DIR_W      = 16,
    parameter int DIR_I      = 2,
    parameter int DIR_F      = DIR_W - 1 - DIR_I,

    parameter int PX_W       = 10,
    parameter int PY_W       = 10,
    parameter int STEP_W     = 5
)(
    input  logic                       clk,
    input  logic                       rst_n,
    input  logic                       en,           // ~stall

    // ----- From marcher -----
    input  logic [1:0]                 status_in,    // 01=HIT, 10=OFFGRID, 00=MISS
    input  logic [IDX_W-1:0]           ix_in,
    input  logic [IDX_W-1:0]           iy_in,
    input  logic signed [H_W-1:0]      h_hit_in,
    input  logic [STEP_W-1:0]          step_count_in,
    input  logic [PX_W-1:0]            px_in,
    input  logic [PY_W-1:0]            py_in,
    input  logic                       valid_in,

    // ----- 4-port BRAM interface -----
    // Port order:
    //   [0] = (ix-1, iy)
    //   [1] = (ix+1, iy)
    //   [2] = (ix,   iy-1)
    //   [3] = (ix,   iy+1)
    output logic [IDX_W*2-1:0]         bram_addr [4],
    output logic                       bram_re   [4],
    input  logic signed [H_W-1:0]      bram_dout [4],

    // ----- To shader -----
    output logic [1:0]                 status_out,
    output logic [IDX_W-1:0]           ix_out,
    output logic [IDX_W-1:0]           iy_out,
    output logic signed [H_W-1:0]      h_hit_out,
    output logic [STEP_W-1:0]          step_count_out,
    output logic signed [DIR_W-1:0]    Nx_out,
    output logic signed [DIR_W-1:0]    Ny_out,
    output logic signed [DIR_W-1:0]    Nz_out,
    output logic [PX_W-1:0]            px_out,
    output logic [PY_W-1:0]            py_out,
    output logic                       valid_out
);

    localparam logic [1:0] ST_HIT = 2'b01;
    localparam logic signed [DIR_W-1:0] NZ_CONST = (1 <<< DIR_F);


    // =================================================================
    //  STAGE 1: latch inputs, compute clamped neighbour indices.
    //  BRAM addresses are combinational from stage-1 registers.
    // =================================================================
    logic [1:0]                 stat_s1;
    logic [IDX_W-1:0]           ix_s1, iy_s1;
    logic signed [H_W-1:0]      hhit_s1;
    logic [STEP_W-1:0]          step_s1;
    logic [PX_W-1:0]            px_s1;
    logic [PY_W-1:0]            py_s1;
    logic                       v_s1;

    logic [IDX_W-1:0]           ix_m1_s1, ix_p1_s1;
    logic [IDX_W-1:0]           iy_m1_s1, iy_p1_s1;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            v_s1 <= 1'b0;
        end else if (en) begin
            // Pass through pipeline payload
            stat_s1  <= status_in;
            ix_s1    <= ix_in;
            iy_s1    <= iy_in;
            hhit_s1  <= h_hit_in;
            step_s1  <= step_count_in;
            px_s1    <= px_in;
            py_s1    <= py_in;
            v_s1     <= valid_in;

            // ix - 1 (saturate at 0)
            if (ix_in == '0)
                ix_m1_s1 <= '0;
            else
                ix_m1_s1 <= ix_in - 1'b1;

            // ix + 1 (saturate at GRID_N-1)
            if (ix_in == GRID_N-1)
                ix_p1_s1 <= ix_in;
            else
                ix_p1_s1 <= ix_in + 1'b1;

            // iy - 1
            if (iy_in == '0)
                iy_m1_s1 <= '0;
            else
                iy_m1_s1 <= iy_in - 1'b1;

            // iy + 1
            if (iy_in == GRID_N-1)
                iy_p1_s1 <= iy_in;
            else
                iy_p1_s1 <= iy_in + 1'b1;
        end
    end

    // BRAM addresses driven combinationally from stage-1 registers.
    // Address layout: {iy, ix} = iy*GRID_N + ix.
    assign bram_addr[0] = {iy_s1,    ix_m1_s1};   // (ix-1, iy)
    assign bram_addr[1] = {iy_s1,    ix_p1_s1};   // (ix+1, iy)
    assign bram_addr[2] = {iy_m1_s1, ix_s1};      // (ix,   iy-1)
    assign bram_addr[3] = {iy_p1_s1, ix_s1};      // (ix,   iy+1)

    assign bram_re[0] = v_s1;
    assign bram_re[1] = v_s1;
    assign bram_re[2] = v_s1;
    assign bram_re[3] = v_s1;


    // =================================================================
    //  STAGE 2: BRAM is performing the read.  Just carry payload forward.
    //  (No BRAM data captured yet.)
    // =================================================================
    logic [1:0]                 stat_s2;
    logic [IDX_W-1:0]           ix_s2, iy_s2;
    logic signed [H_W-1:0]      hhit_s2;
    logic [STEP_W-1:0]          step_s2;
    logic [PX_W-1:0]            px_s2;
    logic [PY_W-1:0]            py_s2;
    logic                       v_s2;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            v_s2 <= 1'b0;
        end else if (en) begin
            stat_s2  <= stat_s1;
            ix_s2    <= ix_s1;
            iy_s2    <= iy_s1;
            hhit_s2  <= hhit_s1;
            step_s2  <= step_s1;
            px_s2    <= px_s1;
            py_s2    <= py_s1;
            v_s2     <= v_s1;
        end
    end


    // =================================================================
    //  STAGE 3: latch BRAM data into pipeline registers.
    //  The addresses were presented at stage-1 posedge; one cycle later
    //  (stage 2) the BRAM is reading; one more cycle later (stage 3)
    //  the data is available on bram_dout.
    // =================================================================
    logic [1:0]                 stat_s3;
    logic [IDX_W-1:0]           ix_s3, iy_s3;
    logic signed [H_W-1:0]      hhit_s3;
    logic [STEP_W-1:0]          step_s3;
    logic [PX_W-1:0]            px_s3;
    logic [PY_W-1:0]            py_s3;
    logic                       v_s3;

    logic signed [H_W-1:0]      h_xm_s3, h_xp_s3;   // h(ix-1, iy), h(ix+1, iy)
    logic signed [H_W-1:0]      h_ym_s3, h_yp_s3;   // h(ix, iy-1), h(ix, iy+1)

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            v_s3 <= 1'b0;
        end else if (en) begin
            stat_s3  <= stat_s2;
            ix_s3    <= ix_s2;
            iy_s3    <= iy_s2;
            hhit_s3  <= hhit_s2;
            step_s3  <= step_s2;
            px_s3    <= px_s2;
            py_s3    <= py_s2;
            v_s3     <= v_s2;

            h_xm_s3  <= bram_dout[0];
            h_xp_s3  <= bram_dout[1];
            h_ym_s3  <= bram_dout[2];
            h_yp_s3  <= bram_dout[3];
        end
    end


    // =================================================================
    //  STAGE 4: compute the surface normal and register the output.
    //
    //  dx_h = h(ix+1, iy) - h(ix-1, iy)     17-bit signed
    //  dy_h = h(ix, iy+1) - h(ix, iy-1)
    //
    //  Then convert hdiff (Q4.11) -> direction (Q2.13) by left-shifting
    //  by DIR_F - H_F = 2 bits.  We use a wider temporary and saturate
    //  to avoid wrap on steep cliffs.
    //
    //  Nx = -dx_dir, Ny = -dy_dir, Nz = 1.0 (constant).
    // =================================================================
    logic signed [H_W:0]           dx_h, dy_h;       // 17-bit
    logic signed [H_W+DIR_W-1:0]   dx_shifted, dy_shifted;
    logic signed [DIR_W-1:0]       nx_calc, ny_calc;

    // Saturation bounds for DIR_W-bit signed
    localparam logic signed [H_W+DIR_W-1:0] SAT_POS =
        $signed({1'b0, {(DIR_W-1){1'b1}}});      // +(2^(DIR_W-1) - 1) = +32767
    localparam logic signed [H_W+DIR_W-1:0] SAT_NEG =
        $signed({{(H_W+1){1'b1}}, {(DIR_W-1){1'b0}}});  // -(2^(DIR_W-1)) = -32768

    always_comb begin
        dx_h = $signed(h_xp_s3) - $signed(h_xm_s3);
        dy_h = $signed(h_yp_s3) - $signed(h_ym_s3);

        // Shift to DIR_F.  With defaults H_F=11, DIR_F=13 -> shift left 2.
        if (DIR_F >= H_F) begin
            dx_shifted = $signed(dx_h) <<< (DIR_F - H_F);
            dy_shifted = $signed(dy_h) <<< (DIR_F - H_F);
        end else begin
            dx_shifted = $signed(dx_h) >>> (H_F - DIR_F);
            dy_shifted = $signed(dy_h) >>> (H_F - DIR_F);
        end

        // Saturate dx_shifted to DIR_W-bit signed
        if (dx_shifted > SAT_POS)
            nx_calc = -SAT_POS[DIR_W-1:0];                 // flip sign for Nx = -dx_dir
        else if (dx_shifted < SAT_NEG)
            nx_calc = -SAT_NEG[DIR_W-1:0];
        else
            nx_calc = -dx_shifted[DIR_W-1:0];

        if (dy_shifted > SAT_POS)
            ny_calc = -SAT_POS[DIR_W-1:0];
        else if (dy_shifted < SAT_NEG)
            ny_calc = -SAT_NEG[DIR_W-1:0];
        else
            ny_calc = -dy_shifted[DIR_W-1:0];
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
        end else if (en) begin
            // Pipeline payload
            status_out     <= stat_s3;
            ix_out         <= ix_s3;
            iy_out         <= iy_s3;
            h_hit_out      <= hhit_s3;
            step_count_out <= step_s3;
            px_out         <= px_s3;
            py_out         <= py_s3;
            valid_out      <= v_s3;

            // Normal
            if (stat_s3 == ST_HIT) begin
                Nx_out <= nx_calc;
                Ny_out <= ny_calc;
                Nz_out <= NZ_CONST;
            end else begin
                Nx_out <= '0;
                Ny_out <= '0;
                Nz_out <= NZ_CONST;
            end
        end
    end

endmodule