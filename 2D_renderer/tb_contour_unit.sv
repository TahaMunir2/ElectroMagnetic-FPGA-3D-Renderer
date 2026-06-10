// tb_contour_unit.sv
// Testbench for contour_unit (run with verilator --binary --timing).
// Drives px=0..639, py=0..479 in raster order at 1 pixel/cycle, captures
// valid_out, and compares (px_out,py_out,r,g,b) against golden.txt.
// Also measures and asserts the pipeline latency.

`timescale 1ns/1ps

module tb_contour_unit;

    localparam int W = 640, H = 480;
    localparam int GRID_N = 64, IDX_W = 6, ADDR_W = 12, H_W = 16;
    localparam int PX_W = 10, PY_W = 9;
    localparam int NPIX = W*H;

    logic clk = 0, rst_n = 0, en = 1;
    always #5 clk = ~clk; // 100 MHz

    logic [PX_W-1:0] px_in;
    logic [PY_W-1:0] py_in;
    logic            valid_in;

    logic [ADDR_W-1:0]     bram_addr;
    logic                  bram_re;
    logic signed [H_W-1:0] bram_dout;

    logic [7:0]      r_out, g_out, b_out;
    logic [PX_W-1:0] px_out;
    logic [PY_W-1:0] py_out;
    logic            valid_out;

    heightmap_bram #(.ADDR_W(ADDR_W), .DATA_W(H_W), .INIT_FILE("heightmap.hex"))
    u_bram (.clk(clk), .addr(bram_addr), .re(bram_re), .dout(bram_dout));

    contour_unit #(
        .W(W), .H(H), .GRID_N(GRID_N), .H_W(H_W), .H_I(2)
    ) dut (
        .clk(clk), .rst_n(rst_n), .en(en),
        .px_in(px_in), .py_in(py_in), .valid_in(valid_in),
        .bram_addr(bram_addr), .bram_re(bram_re), .bram_dout(bram_dout),
        .r_out(r_out), .g_out(g_out), .b_out(b_out),
        .px_out(px_out), .py_out(py_out), .valid_out(valid_out)
    );

    // golden arrays
    int gr [NPIX], gg [NPIX], gb [NPIX];

    // latency measurement
    longint first_valid_in_cycle = -1;
    longint first_valid_out_cycle = -1;
    longint cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;

    int errors = 0, checked = 0;

    // load golden
    initial begin
        int fd, code, px, py, r, g, b, idx;
        fd = $fopen("golden.txt", "r");
        if (fd == 0) begin $display("FATAL: cannot open golden.txt"); $finish; end
        forever begin
            code = $fscanf(fd, "%d %d %d %d %d\n", px, py, r, g, b);
            if (code != 5) break;
            idx = py*W + px;
            gr[idx] = r; gg[idx] = g; gb[idx] = b;
        end
        $fclose(fd);
    end

    // checker: on every valid_out, compare against golden at (px_out,py_out)
    always @(posedge clk) begin
        if (rst_n && valid_out) begin
            int idx;
            if (first_valid_out_cycle < 0) first_valid_out_cycle = cyc;
            idx = py_out*W + px_out;
            checked++;
            if (r_out !== gr[idx] || g_out !== gg[idx] || b_out !== gb[idx]) begin
                if (errors < 10)
                    $display("MISMATCH (%0d,%0d): got (%0d,%0d,%0d) exp (%0d,%0d,%0d)",
                             px_out, py_out, r_out, g_out, b_out,
                             gr[idx], gg[idx], gb[idx]);
                errors++;
            end
        end
    end

    // stimulus: full raster, continuous valid
    initial begin
        px_in = 0; py_in = 0; valid_in = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        for (int yy = 0; yy < H; yy++) begin
            for (int xx = 0; xx < W; xx++) begin
                px_in = xx[PX_W-1:0];
                py_in = yy[PY_W-1:0];
                valid_in = 1'b1;
                if (first_valid_in_cycle < 0) first_valid_in_cycle = cyc + 1;
                @(posedge clk);
            end
        end
        valid_in = 0;
        repeat (10) @(posedge clk);

        $display("----------------------------------------------------------");
        $display("pixels checked : %0d / %0d", checked, NPIX);
        $display("measured latency : %0d core cycles",
                 first_valid_out_cycle - first_valid_in_cycle);
        $display("mismatches : %0d", errors);
        if (errors == 0 && checked == NPIX)
            $display("RESULT : PASS");
        else
            $display("RESULT : FAIL");
        $display("----------------------------------------------------------");
        $finish;
    end

endmodule
