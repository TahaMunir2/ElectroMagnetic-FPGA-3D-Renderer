// ============================================================================
//  tb_normal.sv
//  ----------------------------------------------------------------------------
//  Sequential testbench for normal.sv.
//
//  Drives one record at a time, waits for valid_out, compares:
//      - Nx_out, Ny_out, Nz_out  (allow +/-1 LSB)
//      - status_out, ix_out, iy_out, h_hit_out, step_count_out, px_out, py_out
//        (must pass through unchanged from inputs)
//
//  4-port fake BRAM, each port reads from the shared heightmap.hex.
//
//  Run:
//      iverilog -g2012 -o tb_normal.vvp tb_normal.sv ../normal.sv
//      vvp tb_normal.vvp
// ============================================================================
`timescale 1ns/1ps

module tb_normal;

    localparam int GRID_N  = 256;
    localparam int IDX_W   = 8;
    localparam int H_W     = 16;
    localparam int H_I     = 4;
    localparam int H_F     = H_W - 1 - H_I;
    localparam int DIR_W   = 16;
    localparam int DIR_I   = 2;
    localparam int DIR_F   = DIR_W - 1 - DIR_I;
    localparam int STEP_W  = 5;
    localparam int PX_W    = 10;
    localparam int PY_W    = 10;

    localparam int LATENCY = 3;
    localparam int TOLER   = 1;

    localparam int VPR     = 12;
    localparam int MAX_REC = 1505;
    localparam int MEM_SZ  = MAX_REC * VPR;

    logic clk = 0;
    logic rst_n = 0;
    always #5 clk = ~clk;

    // DUT I/O
    logic                       en;
    logic [1:0]                 status_in;
    logic [IDX_W-1:0]           ix_in, iy_in;
    logic signed [H_W-1:0]      h_hit_in;
    logic [STEP_W-1:0]          step_count_in;
    logic [PX_W-1:0]            px_in;
    logic [PY_W-1:0]            py_in;
    logic                       valid_in;

    logic [IDX_W*2-1:0]         bram_addr [4];
    logic                       bram_re   [4];
    logic signed [H_W-1:0]      bram_dout [4];

    logic [1:0]                 status_out;
    logic [IDX_W-1:0]           ix_out, iy_out;
    logic signed [H_W-1:0]      h_hit_out;
    logic [STEP_W-1:0]          step_count_out;
    logic signed [DIR_W-1:0]    Nx_out, Ny_out, Nz_out;
    logic [PX_W-1:0]            px_out;
    logic [PY_W-1:0]            py_out;
    logic                       valid_out;

    normal dut (.*);

    // Fake 4-port BRAM with intermediate wires (iverilog-friendly)
    logic signed [H_W-1:0] heightmap [0:GRID_N*GRID_N-1];

    genvar gi;
    generate
        for (gi = 0; gi < 4; gi++) begin : g_bram
            wire [IDX_W*2-1:0]  this_addr = bram_addr[gi];
            wire                this_re   = bram_re[gi];
            logic signed [H_W-1:0] this_dout;
            always_ff @(posedge clk) begin
                if (this_re)
                    this_dout <= heightmap[this_addr];
            end
            assign bram_dout[gi] = this_dout;
        end
    endgenerate

    // Vector memory
    logic [15:0] vectors [0:MEM_SZ-1];

    int n_tests, n_pass, n_fail;

    function automatic int abs_diff_signed(input logic signed [DIR_W-1:0] a,
                                            input logic signed [DIR_W-1:0] b);
        int d;
        d = int'(a) - int'(b);
        return (d < 0) ? -d : d;
    endfunction

    task automatic run_one(input int rec_i);
        int base;
        int waited;
        logic [1:0]              in_status;
        logic [IDX_W-1:0]        in_ix, in_iy;
        logic signed [H_W-1:0]   in_h_hit;
        logic [STEP_W-1:0]       in_step;
        logic [PX_W-1:0]         in_px;
        logic [PY_W-1:0]         in_py;
        logic signed [DIR_W-1:0] e_Nx, e_Ny, e_Nz;
        bit ok;

        base = rec_i * VPR;

        @(negedge clk);
        in_status = vectors[base + 0][1:0];
        in_ix     = vectors[base + 1][IDX_W-1:0];
        in_iy     = vectors[base + 2][IDX_W-1:0];
        in_h_hit  = vectors[base + 3];
        in_step   = vectors[base + 4][STEP_W-1:0];
        in_px     = vectors[base + 5][PX_W-1:0];
        in_py     = vectors[base + 6][PY_W-1:0];
        e_Nx      = vectors[base + 7];
        e_Ny      = vectors[base + 8];
        e_Nz      = vectors[base + 9];

        status_in     = in_status;
        ix_in         = in_ix;
        iy_in         = in_iy;
        h_hit_in      = in_h_hit;
        step_count_in = in_step;
        px_in         = in_px;
        py_in         = in_py;
        valid_in      = 1;

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
            if (abs_diff_signed(Nx_out, e_Nx) > TOLER) ok = 0;
            if (abs_diff_signed(Ny_out, e_Ny) > TOLER) ok = 0;
            if (abs_diff_signed(Nz_out, e_Nz) > TOLER) ok = 0;
            if (status_out     !== in_status) ok = 0;
            if (ix_out         !== in_ix)     ok = 0;
            if (iy_out         !== in_iy)     ok = 0;
            if (h_hit_out      !== in_h_hit)  ok = 0;
            if (step_count_out !== in_step)   ok = 0;
            if (px_out         !== in_px)     ok = 0;
            if (py_out         !== in_py)     ok = 0;

            if (ok) n_pass++;
            else begin
                n_fail++;
                if (n_fail <= 10) begin
                    $display("rec %0d FAIL:", rec_i);
                    $display("  in:  stat=%0d ix=%0d iy=%0d h=%0d step=%0d px=%0d py=%0d",
                             in_status, in_ix, in_iy, $signed(in_h_hit), in_step, in_px, in_py);
                    $display("  got: N=(%0d,%0d,%0d) stat=%0d ix=%0d iy=%0d h=%0d step=%0d px=%0d py=%0d",
                             $signed(Nx_out), $signed(Ny_out), $signed(Nz_out),
                             status_out, ix_out, iy_out, $signed(h_hit_out),
                             step_count_out, px_out, py_out);
                    $display("  exp: N=(%0d,%0d,%0d)",
                             $signed(e_Nx), $signed(e_Ny), $signed(e_Nz));
                end
            end
        end

        repeat (LATENCY + 2) @(posedge clk);
    endtask

    initial begin
        int rec_i;
        $dumpfile("tb_normal.vcd");
        $dumpvars(0, tb_normal);

        en = 1;
        status_in = 0; ix_in = 0; iy_in = 0; h_hit_in = 0;
        step_count_in = 0; px_in = 0; py_in = 0; valid_in = 0;
        n_tests = 0; n_pass = 0; n_fail = 0;

        $readmemh("heightmap.hex",     heightmap);
        $readmemh("normal_vectors.hex", vectors);

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
        $display("normal TB: tested=%0d  pass=%0d  fail=%0d",
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
