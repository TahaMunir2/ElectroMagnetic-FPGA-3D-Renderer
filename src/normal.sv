// ============================================================================
//  normal.sv
//  ----------------------------------------------------------------------------
//  Heightmap normal stage.
//
//  Consumes the compact marcher->normal contract for one pixel/ray:
//      - status
//      - hit cell indices (ix, iy)
//      - hit height (h_hit)
//      - pixel coordinates (px, py)
//      - valid
//
//  Then issues 4 neighbouring heightmap reads:
//      (ix-1, iy), (ix+1, iy), (ix, iy-1), (ix, iy+1)
//
//  and computes a gradient-based surface normal:
//      Nx ~ -(h[x+1,y] - h[x-1,y])
//      Ny ~ -(h[x,y+1] - h[x,y-1])
//      Nz = +1.0
//
//  Notes:
//      - One module instance handles a stream of pixels/rays over time,
//        not one whole frame at once.
//      - This module outputs an un-normalized normal in DIR-format.
//        The shader stage can use it directly for approximate lighting.
//      - At the output of the fixed-depth marcher, status=2'b00 means
//        "no hit found within N_STEPS" (MISS), even though the internal
//        marcher code names 2'b00 as ST_MARCHING.
//
//  Interface summary:
//      Inputs from marcher:
//          status_in, ix_in, iy_in, h_hit_in, step_count_in,
//          px_in, py_in, valid_in
//      Outputs to shader:
//          status_out, ix_out, iy_out, h_hit_out, step_count_out,
//          Nx_out, Ny_out, Nz_out,
//          px_out, py_out, valid_out
//
//  Pipeline:
//      Stage 1: latch marcher result, compute clamped neighbour indices
//      Stage 2: BRAM read latency (4 reads return)
//      Stage 3: compute normal, forward to shader
//
//  Total latency: 3 cycles
// ============================================================================

module normal #(
    // ----- Heightmap geometry -----
    parameter int GRID_N     = 256,
    parameter int IDX_W      = $clog2(GRID_N),

    // ----- Heightmap value format -----
    parameter int H_W        = 16,
    parameter int H_I        = 4,
    parameter int H_F        = H_W - 1 - H_I,

    // ----- Fixed-point output format for normal components -----
    // Direction components D and basis vectors: signed Q(I_D).(F_D)
    parameter int DIR_W      = 16,
    parameter int DIR_I      = 2,
    parameter int DIR_F      = DIR_W - 1 - DIR_I,

    // ----- Pixel coordinate widths -----
    parameter int PX_W       = 10,
    parameter int PY_W       = 10,

    // ----- Hit-distance proxy width -----
    parameter int STEP_W     = 5
)(
    input  logic                       clk,
    input  logic                       rst_n,
    input  logic                       en,           // pipeline enable (~stall)

    // ----- From marcher -----
    input  logic [1:0]                 status_in,    // 01=HIT, 10=OFF_GRID, 00=MISS
    input  logic [IDX_W-1:0]           ix_in,
    input  logic [IDX_W-1:0]           iy_in,
    input  logic signed [H_W-1:0]      h_hit_in,
    input  logic [STEP_W-1:0]          step_count_in,
    input  logic [PX_W-1:0]            px_in,
    input  logic [PY_W-1:0]            py_in,
    input  logic                       valid_in,

    // ----- Heightmap BRAM neighbour reads -----
    // Port order:
    //   [0] = (ix-1, iy)
    //   [1] = (ix+1, iy)
    //   [2] = (ix, iy-1)
    //   [3] = (ix, iy+1)
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

    localparam logic [1:0] ST_HIT      = 2'b01;

    localparam logic signed [DIR_W-1:0] NZ_CONST = (1 <<< DIR_F);

    function automatic logic [IDX_W-1:0] clamp_dec (
        input logic [IDX_W-1:0] v
    );
        if (v == '0)
            return '0;
        else
            return v - 1'b1;
    endfunction

    function automatic logic [IDX_W-1:0] clamp_inc (
        input logic [IDX_W-1:0] v
    );
        if (v == GRID_N-1)
            return v;
        else
            return v + 1'b1;
    endfunction

    function automatic logic signed [DIR_W-1:0] hdiff_to_dir (
        input logic signed [H_W:0] hdiff
    );
        logic signed [DIR_W+H_W:0] tmp;
        begin
            tmp = hdiff;
            if (DIR_F >= H_F)
                tmp = tmp <<< (DIR_F - H_F);
            else
                tmp = tmp >>> (H_F - DIR_F);
            return tmp[DIR_W-1:0];
        end
    endfunction

    // =================================================================
    //  STAGE 1 -- latch marcher metadata and compute neighbour addresses
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
            stat_s1  <= status_in;
            ix_s1    <= ix_in;
            iy_s1    <= iy_in;
            hhit_s1  <= h_hit_in;
            step_s1  <= step_count_in;
            px_s1    <= px_in;
            py_s1    <= py_in;
            v_s1     <= valid_in;

            ix_m1_s1 <= clamp_dec(ix_in);
            ix_p1_s1 <= clamp_inc(ix_in);
            iy_m1_s1 <= clamp_dec(iy_in);
            iy_p1_s1 <= clamp_inc(iy_in);
        end
    end

    assign bram_addr[0] = {iy_s1,    ix_m1_s1};
    assign bram_addr[1] = {iy_s1,    ix_p1_s1};
    assign bram_addr[2] = {iy_m1_s1, ix_s1   };
    assign bram_addr[3] = {iy_p1_s1, ix_s1   };

    // Keep the read pattern simple: always read when the pipeline slot is valid.
    assign bram_re[0] = v_s1;
    assign bram_re[1] = v_s1;
    assign bram_re[2] = v_s1;
    assign bram_re[3] = v_s1;

    // =================================================================
    //  STAGE 2 -- capture the 4 neighbouring heights from BRAM
    // =================================================================
    logic [1:0]                 stat_s2;
    logic [IDX_W-1:0]           ix_s2, iy_s2;
    logic signed [H_W-1:0]      hhit_s2;
    logic [STEP_W-1:0]          step_s2;
    logic [PX_W-1:0]            px_s2;
    logic [PY_W-1:0]            py_s2;
    logic                       v_s2;

    logic signed [H_W-1:0]      h_xm_s2, h_xp_s2;
    logic signed [H_W-1:0]      h_ym_s2, h_yp_s2;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            v_s2 <= 1'b0;
        end else if (en) begin
            stat_s2 <= stat_s1;
            ix_s2   <= ix_s1;
            iy_s2   <= iy_s1;
            hhit_s2 <= hhit_s1;
            step_s2 <= step_s1;
            px_s2   <= px_s1;
            py_s2   <= py_s1;
            v_s2    <= v_s1;

            h_xm_s2 <= bram_dout[0];
            h_xp_s2 <= bram_dout[1];
            h_ym_s2 <= bram_dout[2];
            h_yp_s2 <= bram_dout[3];
        end
    end

    // =================================================================
    //  STAGE 3 -- central-difference gradient -> normal
    // =================================================================
    logic signed [H_W:0] dx_h_s3;
    logic signed [H_W:0] dy_h_s3;
    logic signed [DIR_W-1:0] nx_s3, ny_s3;

    always_comb begin
        dx_h_s3 = $signed(h_xp_s2) - $signed(h_xm_s2);
        dy_h_s3 = $signed(h_yp_s2) - $signed(h_ym_s2);

        nx_s3 = -hdiff_to_dir(dx_h_s3);
        ny_s3 = -hdiff_to_dir(dy_h_s3);
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
        end else if (en) begin
            status_out <= stat_s2;
            ix_out     <= ix_s2;
            iy_out     <= iy_s2;
            h_hit_out  <= hhit_s2;
            step_count_out <= step_s2;
            px_out     <= px_s2;
            py_out     <= py_s2;
            valid_out  <= v_s2;

            if (stat_s2 == ST_HIT) begin
                Nx_out <= nx_s3;
                Ny_out <= ny_s3;
                Nz_out <= NZ_CONST;
            end else begin
                Nx_out <= '0;
                Ny_out <= '0;
                Nz_out <= NZ_CONST;
            end
        end
    end

endmodule
