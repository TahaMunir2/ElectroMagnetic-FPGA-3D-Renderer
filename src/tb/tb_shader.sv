// ============================================================================
//  tb_shader.sv
//  ----------------------------------------------------------------------------
//  Sequential testbench for shader.sv.
//
//  Drives one record at a time, waits for valid_out, compares:
//      - r_out, g_out, b_out  (allow +/-1 LSB)
//      - px_out, py_out       (must pass through)
//
//  No BRAM in this module — pure arithmetic.
//
//  Run:
//      iverilog -g2012 -o tb_shader.vvp tb_shader.sv ../shader.sv
//      vvp tb_shader.vvp
// ============================================================================
`timescale 1ns/1ps

module tb_shader;

    localparam int H_W     = 16;
    localparam int H_I     = 4;
    localparam int H_F     = H_W - 1 - H_I;
    localparam int DIR_W   = 16;
    localparam int DIR_I   = 2;
    localparam int DIR_F   = DIR_W - 1 - DIR_I;
    localparam int N_STEPS = 16;
    localparam int STEP_W  = 5;
    localparam int PX_W    = 10;
    localparam int PY_W    = 10;

    localparam int LATENCY = 1;     // shader is 1 cycle
    localparam int TOLER   = 1;

    localparam int VPR     = 14;
    localparam int MAX_REC = 2100;
    localparam int MEM_SZ  = MAX_REC * VPR;

    logic clk = 0;
    logic rst_n = 0;
    always #5 clk = ~clk;

    logic                       en;
    logic [1:0]                 status_in;
    logic signed [H_W-1:0]      h_hit_in;
    logic [STEP_W-1:0]          step_count_in;
    logic signed [DIR_W-1:0]    Nx_in, Ny_in, Nz_in;
    logic [PX_W-1:0]            px_in;
    logic [PY_W-1:0]            py_in;
    logic                       valid_in;
    logic signed [DIR_W-1:0]    sun_dx, sun_dy, sun_dz;
    logic [7:0]                 r_out, g_out, b_out;
    logic [PX_W-1:0]            px_out;
    logic [PY_W-1:0]            py_out;
    logic                       valid_out;

    shader dut (.*);

    logic [15:0] vectors [0:MEM_SZ-1];

    int n_tests, n_pass, n_fail;

    function automatic int abs_diff_u8(input logic [7:0] a, input logic [7:0] b);
        int d;
        d = int'(a) - int'(b);
        return (d < 0) ? -d : d;
    endfunction

    task automatic run_one(input int rec_i);
        int base;
        int waited;
        logic [1:0]              in_status;
        logic signed [H_W-1:0]   in_h_hit;
        logic [STEP_W-1:0]       in_step;
        logic signed [DIR_W-1:0] in_Nx, in_Ny, in_Nz;
        logic signed [DIR_W-1:0] in_sx, in_sy, in_sz;
        logic [PX_W-1:0]         in_px;
        logic [PY_W-1:0]         in_py;
        logic [7:0]              e_r, e_g, e_b;
        bit ok;

        base = rec_i * VPR;

        @(negedge clk);
        in_status = vectors[base + 0][1:0];
        in_h_hit  = vectors[base + 1];
        in_step   = vectors[base + 2][STEP_W-1:0];
        in_Nx     = vectors[base + 3];
        in_Ny     = vectors[base + 4];
        in_Nz     = vectors[base + 5];
        in_sx     = vectors[base + 6];
        in_sy     = vectors[base + 7];
        in_sz     = vectors[base + 8];
        in_px     = vectors[base + 9][PX_W-1:0];
        in_py     = vectors[base + 10][PY_W-1:0];
        e_r       = vectors[base + 11][7:0];
        e_g       = vectors[base + 12][7:0];
        e_b       = vectors[base + 13][7:0];

        status_in     = in_status;
        h_hit_in      = in_h_hit;
        step_count_in = in_step;
        Nx_in         = in_Nx;
        Ny_in         = in_Ny;
        Nz_in         = in_Nz;
        sun_dx        = in_sx;
        sun_dy        = in_sy;
        sun_dz        = in_sz;
        px_in         = in_px;
        py_in         = in_py;




        valid_in = 1;

        // Debug: dump combinational internals while inputs are still applied
        if (rec_i == 0) begin
            #1;  // small delay to let combinational logic settle
            $display("=== Rec 0 internal trace ===");
            $display("  bright_q     = %0d", $signed(dut.bright_q));
            $display("  bright_u8    = %0d", dut.bright_u8);
            $display("  light_u8     = %0d", dut.light_u8);
            $display("  altitude_u8  = %0d", dut.altitude_u8);
            $display("  base   r,g,b = %0d, %0d, %0d", dut.base_r, dut.base_g, dut.base_b);
            $display("  fog_u8       = %0d", dut.fog_u8);
            $display("  fogged r,g,b = %0d, %0d, %0d", dut.fogged_r, dut.fogged_g, dut.fogged_b);
            $display("  lit    r,g,b = %0d, %0d, %0d", dut.lit_r, dut.lit_g, dut.lit_b);
        end

        @(negedge clk);
        valid_in = 0;

        waited = 0;
        while (!valid_out && waited < 2*LATENCY + 5) begin
            @(posedge clk);
            waited++;
        end

        if (!valid_out) begin
            $display("rec %0d: TIMEOUT waiting for valid_out", rec_i);
            n_fail++;
        end else begin
            n_tests++;
            ok = 1;
            if (abs_diff_u8(r_out, e_r) > TOLER) ok = 0;
            if (abs_diff_u8(g_out, e_g) > TOLER) ok = 0;
            if (abs_diff_u8(b_out, e_b) > TOLER) ok = 0;
            if (px_out !== in_px) ok = 0;
            if (py_out !== in_py) ok = 0;

            if (ok) n_pass++;
            else begin
                n_fail++;
                if (n_fail <= 10) begin
                    $display("rec %0d FAIL:", rec_i);
                    $display("  in:  stat=%0d h=%0d step=%0d N=(%0d,%0d,%0d) sun=(%0d,%0d,%0d)",
                             in_status, $signed(in_h_hit), in_step,
                             $signed(in_Nx), $signed(in_Ny), $signed(in_Nz),
                             $signed(in_sx), $signed(in_sy), $signed(in_sz));
                    $display("  got: rgb=(%0d,%0d,%0d) px=%0d py=%0d",
                             r_out, g_out, b_out, px_out, py_out);
                    $display("  exp: rgb=(%0d,%0d,%0d)", e_r, e_g, e_b);
                end
            end
        end

        repeat (LATENCY + 1) @(posedge clk);
    endtask

    initial begin
        int rec_i;
        $dumpfile("tb_shader.vcd");
        $dumpvars(0, tb_shader);

        en = 1;
        status_in = 0; h_hit_in = 0; step_count_in = 0;
        Nx_in = 0; Ny_in = 0; Nz_in = 0;
        sun_dx = 0; sun_dy = 0; sun_dz = 0;
        px_in = 0; py_in = 0; valid_in = 0;
        n_tests = 0; n_pass = 0; n_fail = 0;

        $readmemh("shader_vectors.hex", vectors);

        rst_n = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        rec_i = 0;
        while (rec_i < MAX_REC && (^vectors[rec_i*VPR] !== 1'bx)) begin
            run_one(rec_i);
            rec_i++;
        end

        $display("================================================");
        $display("shader TB: tested=%0d  pass=%0d  fail=%0d",
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
