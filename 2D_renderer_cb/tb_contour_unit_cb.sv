// Testbench for contour_unit writable palette (run with verilator --binary --timing).
// Phase A: render full raster with the built-in default palette -> check golden_p0.
// Then write palette P1 (cividis) through {pal_we,pal_idx,pal_rgb}.
// Phase B: render full raster again -> check golden_p1.
// Proves the palette input recolours the output.

`timescale 1ns/1ps
`include "palettes.svh"

module tb_contour_unit;
    localparam int W=640, H=480, GRID_N=64, IDX_W=6, ADDR_W=12, H_W=16;
    localparam int PX_W=10, PY_W=9, NPIX=W*H;

    logic clk=0, rst_n=0, en=1;
    always #5 clk=~clk;

    logic [PX_W-1:0] px_in; logic [PY_W-1:0] py_in; logic valid_in;
    logic [ADDR_W-1:0] bram_addr; logic bram_re; logic signed [H_W-1:0] bram_dout;
    logic pal_we; logic [3:0] pal_idx; logic [23:0] pal_rgb;
    logic [7:0] r_out,g_out,b_out; logic [PX_W-1:0] px_out; logic [PY_W-1:0] py_out; logic valid_out;

    heightmap_bram #(.ADDR_W(ADDR_W), .DATA_W(H_W), .INIT_FILE("heightmap.hex"))
    u_bram (.clk(clk), .addr(bram_addr), .re(bram_re), .dout(bram_dout));

    contour_unit #(.W(W), .H(H), .GRID_N(GRID_N), .H_W(H_W), .H_I(2))
    dut (.clk(clk), .rst_n(rst_n), .en(en),
        .px_in(px_in), .py_in(py_in), .valid_in(valid_in),
        .bram_addr(bram_addr), .bram_re(bram_re), .bram_dout(bram_dout),
        .pal_we(pal_we), .pal_idx(pal_idx), .pal_rgb(pal_rgb),
        .r_out(r_out), .g_out(g_out), .b_out(b_out),
        .px_out(px_out), .py_out(py_out), .valid_out(valid_out));

    int gr[NPIX], gg[NPIX], gb[NPIX];
    int errors=0, checked=0;
    int check_active=0;

    task load_golden(input string fname);
        int fd, code, px,py,r,g,b,idx;
        fd=$fopen(fname,"r");
        if (fd==0) begin $display("FATAL: cannot open %s", fname); $finish; end
        forever begin
            code=$fscanf(fd,"%d %d %d %d %d\n",px,py,r,g,b);
            if (code!=5) break;
            idx=py*W+px; gr[idx]=r; gg[idx]=g; gb[idx]=b;
        end
        $fclose(fd);
    endtask

    // checker
    always @(posedge clk) begin
        if (rst_n && valid_out && check_active) begin
            int idx; idx=py_out*W+px_out; checked++;
            if (r_out!==gr[idx]||g_out!==gg[idx]||b_out!==gb[idx]) begin
                if (errors<5) $display("MISMATCH (%0d,%0d): got(%0d,%0d,%0d) exp(%0d,%0d,%0d)",
                    px_out,py_out,r_out,g_out,b_out,gr[idx],gg[idx],gb[idx]);
                errors++;
            end
        end
    end

    task raster(input string phase);
        checked=0; errors=0; check_active=1;
        for (int yy=0; yy<H; yy++)
            for (int xx=0; xx<W; xx++) begin
                px_in=xx[PX_W-1:0]; py_in=yy[PY_W-1:0]; valid_in=1'b1;
                @(posedge clk);
            end
        valid_in=0;
        repeat (6) @(posedge clk);
        check_active=0;
        $display("[%s] checked %0d/%0d  mismatches %0d  -> %s",
            phase, checked, NPIX, errors, (errors==0 && checked==NPIX)?"PASS":"FAIL");
    endtask

    initial begin
        px_in=0; py_in=0; valid_in=0; pal_we=0; pal_idx=0; pal_rgb=0;
        repeat (4) @(posedge clk); rst_n=1; @(posedge clk);

        // Phase A: default palette
        load_golden("golden_p0.txt");
        raster("A default palette");

        // write palette P1 (cividis) one entry per cycle
        for (int k=0; k<16; k++) begin
            pal_we=1'b1; pal_idx=k[3:0]; pal_rgb=PAL_P1[k];
            @(posedge clk);
        end
        pal_we=0; repeat (4) @(posedge clk);

        // Phase B: rewritten palette
        load_golden("golden_p1.txt");
        raster("B rewritten palette");

        $display("----------------------------------------------------------");
        $display("RESULT : palette input %s",
            (errors==0)?"WORKS (output recoloured to match golden)":"FAILED");
        $finish;
    end
endmodule
