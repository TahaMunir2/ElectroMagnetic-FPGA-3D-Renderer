// ============================================================================
//  normal_fwd.sv  (forward-interpolation normal, NO BRAM ports)
//  ----------------------------------------------------------------------------
//  Same forward-difference normal as normal4:
//      Nx = -(h10 - h00),  Ny = -(h01 - h00),  Nz = +1
//  but the three corners are FORWARDED from the marcher (march_step32 carries
//  the hit-cell corners) instead of being re-read from the heightmap.  This
//  removes the normal's 2 BRAM ports / 1 copy entirely.
//
//  Kept at 5 pipeline stages so total renderer latency is unchanged vs D4
//  (ray_gen 4 + marcher 11*N + normal 5 + shader 5).  Stages 1-4 just carry the
//  corners + payload; stage 5 does the identical saturating forward-difference.
//  Saturation/scaling arithmetic is byte-identical to normal4 stage 5.
// ============================================================================

module normal_fwd #(
    parameter int GRID_N     = 128,
    parameter int IDX_W      = $clog2(GRID_N),

    parameter int H_W        = 16,
    parameter int H_I        = 2,
    parameter int H_F        = H_W - 1 - H_I,

    parameter int DIR_W      = 16,
    parameter int DIR_I      = 2,
    parameter int DIR_F      = DIR_W - 1 - DIR_I,

    parameter int PX_W       = 10,
    parameter int PY_W       = 10,
    parameter int STEP_W     = 6
)(
    input  logic                       clk,
    input  logic                       rst_n,
    input  logic                       en,

    input  logic [1:0]                 status_in,
    input  logic [IDX_W-1:0]           ix_in,
    input  logic [IDX_W-1:0]           iy_in,
    input  logic signed [H_W-1:0]      h_hit_in,       // smooth height (passthrough)
    // hit-cell corners forwarded by the marcher
    input  logic signed [H_W-1:0]      h00_in,
    input  logic signed [H_W-1:0]      h10_in,
    input  logic signed [H_W-1:0]      h01_in,
    input  logic [STEP_W-1:0]          step_count_in,
    input  logic [PX_W-1:0]            px_in,
    input  logic [PY_W-1:0]            py_in,
    input  logic                       valid_in,

    output logic [1:0]                 status_out,
    output logic [IDX_W-1:0]           ix_out,
    output logic [IDX_W-1:0]           iy_out,
    output logic signed [H_W-1:0]      h_hit_out,
    output logic signed [H_W-1:0]      h_interp_out,
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

    // Generic per-stage carry bundle (payload + 3 corners).
    typedef struct packed {
        logic [1:0]            stat;
        logic [IDX_W-1:0]      ix;
        logic [IDX_W-1:0]      iy;
        logic signed [H_W-1:0] hhit;
        logic signed [H_W-1:0] h00;
        logic signed [H_W-1:0] h10;
        logic signed [H_W-1:0] h01;
        logic [STEP_W-1:0]     step;
        logic [PX_W-1:0]       px;
        logic [PY_W-1:0]       py;
        logic                  v;
    } payload_t;

    payload_t s1, s2, s3, s4;

    // ----- Stage 1: latch -----
    always_ff @(posedge clk) begin
        if (!rst_n) s1.v <= 1'b0;
        else if (en) begin
            s1.stat <= status_in; s1.ix <= ix_in; s1.iy <= iy_in;
            s1.hhit <= h_hit_in;
            s1.h00  <= h00_in; s1.h10 <= h10_in; s1.h01 <= h01_in;
            s1.step <= step_count_in; s1.px <= px_in; s1.py <= py_in;
            s1.v    <= valid_in;
        end
    end

    // ----- Stages 2-4: carry (latency match) -----
    always_ff @(posedge clk) begin
        if (!rst_n) begin s2.v <= 1'b0; s3.v <= 1'b0; s4.v <= 1'b0; end
        else if (en) begin
            s2 <= s1; s3 <= s2; s4 <= s3;
        end
    end

    // ----- Stage 5: forward-difference normal + saturate (== normal4) -----
    logic signed [H_W:0]           dx_h_comb, dy_h_comb;
    logic signed [H_W+DIR_W-1:0]   dx_shifted, dy_shifted;
    logic signed [DIR_W-1:0]       nx_calc, ny_calc;

    localparam logic signed [H_W+DIR_W-1:0] SAT_POS =
        $signed({1'b0, {(DIR_W-1){1'b1}}});
    localparam logic signed [H_W+DIR_W-1:0] SAT_NEG =
        $signed({{(H_W+1){1'b1}}, {(DIR_W-1){1'b0}}});

    always_comb begin
        dx_h_comb = $signed(s4.h10) - $signed(s4.h00);
        dy_h_comb = $signed(s4.h01) - $signed(s4.h00);

        if (DIR_F >= H_F) begin
            dx_shifted = $signed(dx_h_comb) <<< (DIR_F - H_F);
            dy_shifted = $signed(dy_h_comb) <<< (DIR_F - H_F);
        end else begin
            dx_shifted = $signed(dx_h_comb) >>> (H_F - DIR_F);
            dy_shifted = $signed(dy_h_comb) >>> (H_F - DIR_F);
        end

        if (dx_shifted > SAT_POS)      nx_calc = -SAT_POS[DIR_W-1:0];
        else if (dx_shifted < SAT_NEG) nx_calc = -SAT_NEG[DIR_W-1:0];
        else                           nx_calc = -dx_shifted[DIR_W-1:0];

        if (dy_shifted > SAT_POS)      ny_calc = -SAT_POS[DIR_W-1:0];
        else if (dy_shifted < SAT_NEG) ny_calc = -SAT_NEG[DIR_W-1:0];
        else                           ny_calc = -dy_shifted[DIR_W-1:0];
    end

    always_ff @(posedge clk) begin
        if (!rst_n) valid_out <= 1'b0;
        else if (en) begin
            status_out     <= s4.stat;
            ix_out         <= s4.ix;
            iy_out         <= s4.iy;
            h_hit_out      <= s4.hhit;
            h_interp_out   <= s4.hhit;
            step_count_out <= s4.step;
            px_out         <= s4.px;
            py_out         <= s4.py;
            valid_out      <= s4.v;

            if (s4.stat == ST_HIT) begin
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
