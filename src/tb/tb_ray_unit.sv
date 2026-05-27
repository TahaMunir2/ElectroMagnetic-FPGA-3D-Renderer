// ============================================================================
//  tb_ray_unit.sv
//  ----------------------------------------------------------------------------
//  End-to-end testbench for ray_unit.
//
//  Drives one pixel at a time, waits for valid_out, compares RGB against
//  the Python golden (ray_unit_vectors.hex).
//
//  Provides 20 fake BRAM ports (16 marcher + 4 normal), all serving the
//  same heightmap (loaded from heightmap.hex).
//
//  Run with:
//    See README for build instructions.
// ============================================================================
`timescale 1ns/1ps

module tb_ray_unit;

    // ----- Test parameters (must match Python golden) -----
    localparam int W       = 4;
    localparam int H       = 4;
    localparam int POS_W   = 16;
    localparam int POS_I   = 2;
    localparam int POS_F   = POS_W - 1 - POS_I;
    localparam int DIR_W   = 16;
    localparam int DIR_I   = 2;
    localparam int DIR_F   = DIR_W - 1 - DIR_I;
    localparam int GRID_N  = 4;
    localparam int IDX_W   = 2;
    localparam int H_W     = 16;
    localparam int H_I     = 2;
    localparam int H_F     = H_W - 1 - H_I;
    localparam int N_STEPS = 4;
    localparam int STEP_W  = 3;
    localparam int PX_W    = 2;
    localparam int PY_W    = 2;

    localparam int LATENCY = 4 + 4*N_STEPS + 4 + 5;   // ray_gen + marcher + normal + shader = 29
    localparam int TOLER   = 1;

    localparam int VPR     = 5;       // px, py, r, g, b (each 16-bit)
    localparam int MAX_REC = 64;
    localparam int MEM_SZ  = MAX_REC * VPR;

    // K_U, K_V for 4x4 / 90 FOV
    localparam logic signed [15:0] K_U_VAL = 16'sd16384;
    localparam logic signed [15:0] K_V_VAL = 16'sd16384;

    // ----- Clock / reset -----
    logic clk = 0;
    logic rst_n = 0;
    always #5 clk = ~clk;

    // ----- DUT I/O -----
    logic                       en;
    logic signed [POS_W-1:0]    Ox, Oy, Oz;
    logic signed [DIR_W-1:0]    fwd_x, fwd_y, fwd_z;
    logic signed [DIR_W-1:0]    right_x, right_y, right_z;
    logic signed [DIR_W-1:0]    up_x, up_y, up_z;
    logic signed [DIR_W-1:0]    sun_dx, sun_dy, sun_dz;
    logic [PX_W-1:0]            px_in;
    logic [PY_W-1:0]            py_in;
    logic                       valid_in;

    logic [IDX_W*2-1:0]         marcher_bram_addr [N_STEPS];
    logic                       marcher_bram_re   [N_STEPS];
    logic signed [H_W-1:0]      marcher_bram_dout [N_STEPS];
    logic [IDX_W*2-1:0]         normal_bram_addr  [4];
    logic                       normal_bram_re    [4];
    logic signed [H_W-1:0]      normal_bram_dout  [4];

    logic [7:0]                 r_out, g_out, b_out;
    logic [PX_W-1:0]            px_out;
    logic [PY_W-1:0]            py_out;
    logic                       valid_out;

    ray_unit #(
        .W      (W), .H(H),
        .POS_W  (POS_W), .POS_I(POS_I),
        .DIR_W  (DIR_W), .DIR_I(DIR_I),
        .GRID_N (GRID_N),
        .H_W    (H_W),   .H_I(H_I),
        .N_STEPS(N_STEPS),
        .K_U    (K_U_VAL),
        .K_V    (K_V_VAL)
    ) dut (.*);

    // ----- Fake BRAM (shared by all 20 ports) -----
    logic signed [H_W-1:0] heightmap [0:GRID_N*GRID_N-1];

    genvar gi;
    generate
        for (gi = 0; gi < N_STEPS; gi++) begin : g_mc_bram
            wire [IDX_W*2-1:0]   addr_w = marcher_bram_addr[gi];
            wire                 re_w   = marcher_bram_re[gi];
            logic signed [H_W-1:0] dout_r;
            always_ff @(posedge clk) begin
                if (re_w)
                    dout_r <= heightmap[addr_w];
            end
            assign marcher_bram_dout[gi] = dout_r;
        end
        for (gi = 0; gi < 4; gi++) begin : g_nm_bram
            wire [IDX_W*2-1:0]   addr_w = normal_bram_addr[gi];
            wire                 re_w   = normal_bram_re[gi];
            logic signed [H_W-1:0] dout_r;
            always_ff @(posedge clk) begin
                if (re_w)
                    dout_r <= heightmap[addr_w];
            end
            assign normal_bram_dout[gi] = dout_r;
        end
    endgenerate

    // ----- Vector storage -----
    logic [15:0] vectors [0:MEM_SZ-1];

    // ----- Stats -----
    int n_tests, n_pass, n_fail;

    function automatic int abs_diff_u8(input logic [7:0] a, input logic [7:0] b);
        int d;
        d = int'(a) - int'(b);
        return (d < 0) ? -d : d;
    endfunction

    // ----- Drive one pixel and check -----
    task automatic run_one(input int rec_i);
        int base, waited;
        logic [PX_W-1:0] in_px;
        logic [PY_W-1:0] in_py;
        logic [7:0]      e_r, e_g, e_b;
        bit ok;

        base = rec_i * VPR;

        @(negedge clk);
        in_px = vectors[base + 0][PX_W-1:0];
        in_py = vectors[base + 1][PY_W-1:0];
        e_r   = vectors[base + 2][7:0];
        e_g   = vectors[base + 3][7:0];
        e_b   = vectors[base + 4][7:0];

        px_in    = in_px;
        py_in    = in_py;
        valid_in = 1;

        @(negedge clk);
        valid_in = 0;

        waited = 0;
        while (!valid_out && waited < 2*LATENCY + 20) begin
            @(posedge clk);
            waited++;
        end

        if (!valid_out) begin
            $display("rec %0d (px=%0d,py=%0d): TIMEOUT", rec_i, in_px, in_py);
            n_fail++;
        end else begin
            n_tests++;
            ok = 1;
            if (abs_diff_u8(r_out, e_r) > TOLER) ok = 0;
            if (abs_diff_u8(g_out, e_g) > TOLER) ok = 0;
            if (abs_diff_u8(b_out, e_b) > TOLER) ok = 0;

            if (ok) begin
                n_pass++;
                $display("rec %0d (px=%0d,py=%0d): PASS  rgb=(%0d,%0d,%0d)",
                         rec_i, in_px, in_py, r_out, g_out, b_out);
            end else begin
                n_fail++;
                $display("rec %0d (px=%0d,py=%0d): FAIL  got=(%0d,%0d,%0d) exp=(%0d,%0d,%0d)",
                         rec_i, in_px, in_py, r_out, g_out, b_out, e_r, e_g, e_b);
            end
        end

        repeat (LATENCY + 5) @(posedge clk);
    endtask

    // ----- Main -----
    initial begin
        int rec_i;

        // Defaults
        en = 1;
        Ox = 0; Oy = 0; Oz = 0;
        fwd_x = 0; fwd_y = 0; fwd_z = 0;
        right_x = 0; right_y = 0; right_z = 0;
        up_x = 0; up_y = 0; up_z = 0;
        sun_dx = 0; sun_dy = 0; sun_dz = 16'sd8192;   // sun overhead
        px_in = 0; py_in = 0; valid_in = 0;
        n_tests = 0; n_pass = 0; n_fail = 0;

        // Load heightmap and vectors
        $readmemh("heightmap.hex",       heightmap);
        $readmemh("ray_unit_vectors.hex", vectors);

        // Camera setup (from Python golden output)
        Ox      = 16'sd8192;
        Oy      = 16'sd8192;
        Oz      = 16'sd8192;
        fwd_x   = -16'sd4730;
        fwd_y   = -16'sd4730;
        fwd_z   = -16'sd4730;
        right_x = -16'sd5793;
        right_y =  16'sd5793;
        right_z =  16'sd0;
        up_x    = -16'sd3344;
        up_y    = -16'sd3344;
        up_z    =  16'sd6689;

        // Reset
        rst_n = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        rec_i = 0;
        while (rec_i < W*H && (^vectors[rec_i*VPR] !== 1'bx)) begin
            run_one(rec_i);
            rec_i++;
        end

        $display("================================================");
        $display("ray_unit TB: tested=%0d  pass=%0d  fail=%0d",
                 n_tests, n_pass, n_fail);
        if (n_fail == 0 && n_tests > 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL");
        $display("================================================");
        $finish;
    end

    initial begin
        #200_000_000;
        $display("WATCHDOG TIMEOUT");
        $finish;
    end

endmodule
