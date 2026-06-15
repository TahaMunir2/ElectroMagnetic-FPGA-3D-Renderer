`timescale 1ns/1ps
// Smoke test: s_mag_to_heightmap_bridge copies the s_mag FRONT buffer into a
// heightmap_bram_rw during vblank, applying the magnitude->height shift.
module tb_bridge;
    localparam ADDR_W = 12, DATA_W = 16, DEPTH = 4096;
    localparam GUARD = 8;          // small guard so the test is short
    localparam SHIFT = 1;

    logic clk = 0; always #5 clk = ~clk;
    logic rst;

    logic vblank;
    logic read_sel;
    logic signed [4:0] height_ctl;

    // bridge <-> s_mag port B
    logic [ADDR_W-1:0] s_mag_addrb;
    logic              s_mag_enb;
    logic signed [DATA_W-1:0] a_doutb, b_doutb;

    // bridge -> heightmap broadcast write
    logic              hm_we;
    logic [ADDR_W-1:0] hm_waddr;
    logic signed [DATA_W-1:0] hm_wdata;
    logic              busy;

    // s_mag buffer A (preloaded with a ramp via port A)
    logic        a_ena, a_wea;
    logic [ADDR_W-1:0] a_addra;
    logic signed [DATA_W-1:0] a_dina;
    smag_bram u_smag_a (
        .clka(clk), .ena(a_ena), .addra(a_addra), .wea(a_wea), .dina(a_dina),
        .clkb(clk), .enb(s_mag_enb), .addrb(s_mag_addrb), .doutb(a_doutb));

    // s_mag buffer B (unused front in this test; tie writes off)
    smag_bram u_smag_b (
        .clka(clk), .ena(1'b0), .addra('0), .wea(1'b0), .dina('0),
        .clkb(clk), .enb(s_mag_enb), .addrb(s_mag_addrb), .doutb(b_doutb));

    // a heightmap copy acting as the spy/destination
    logic [ADDR_W-1:0] hm_raddr;
    logic              hm_re;
    logic signed [DATA_W-1:0] hm_rdout;
    heightmap_bram_rw u_hm (
        .clk(clk), .we(hm_we), .waddr(hm_waddr), .wdata(hm_wdata),
        .addr(hm_raddr), .re(hm_re), .dout(hm_rdout));

    s_mag_to_heightmap_bridge #(
        .ADDR_W(ADDR_W), .DATA_W(DATA_W), .GUARD_CYCLES(GUARD), .HEIGHT_SHIFT(SHIFT)
    ) dut (
        .clk(clk), .rst(rst), .height_ctl(height_ctl), .vblank(vblank), .read_sel(read_sel),
        .s_mag_addrb(s_mag_addrb), .s_mag_enb(s_mag_enb),
        .s_mag_a_doutb(a_doutb), .s_mag_b_doutb(b_doutb),
        .hm_we(hm_we), .hm_waddr(hm_waddr), .hm_wdata(hm_wdata), .busy(busy));

    integer i;
    integer writes;
    logic [DATA_W-1:0] expect_mem [0:DEPTH-1];
    logic              seen [0:DEPTH-1];

    // count + check writes against expected scaled values
    always @(posedge clk) begin
        if (hm_we) begin
            writes = writes + 1;
            seen[hm_waddr] = 1'b1;
            if (writes <= 6 || hm_waddr >= DEPTH-4)
                $display("[w%0d] t=%0t waddr=%0d wdata=%0d exp=%0d  addrb=%0d enb=%b a_doutb=%0d sel=%b",
                         writes, $time, hm_waddr, hm_wdata, expect_mem[hm_waddr],
                         s_mag_addrb, s_mag_enb, a_doutb, dut.sel_l);
            if (hm_wdata !== expect_mem[hm_waddr]) begin
                $display("MISMATCH addr=%0d got=%0d exp=%0d", hm_waddr, hm_wdata, expect_mem[hm_waddr]);
                $fatal(1);
            end
        end
    end

    initial begin
        rst = 1; vblank = 0; read_sel = 0; writes = 0;
        height_ctl = -5'sd1;   // -1 => divide by 2 (attenuate path), matches old >>1
        for (i = 0; i < DEPTH; i = i + 1) seen[i] = 1'b0;
        a_ena = 0; a_wea = 0; a_addra = 0; a_dina = 0;
        hm_re = 0; hm_raddr = 0;
        repeat (4) @(posedge clk);
        rst = 0;
        @(posedge clk);

        // preload buffer A with a ramp:  mem[i] = (i*7) & 0x1FFF  (kept positive)
        // Drive stimulus on the negedge so address/data are stable around the
        // posedge the BRAM samples (avoids a tb/clock delta race).
        for (i = 0; i < DEPTH; i = i + 1) begin
            @(negedge clk);
            a_ena = 1; a_wea = 1; a_addra = i; a_dina = (i*7) & 16'h1FFF;
            expect_mem[i] = ((i*7) & 16'h1FFF) >> SHIFT;   // bridge applies >>SHIFT
        end
        @(negedge clk);
        a_ena = 0; a_wea = 0;
        @(posedge clk);

        // read_sel=0 -> front buffer is A
        read_sel = 0;

        // pulse vblank high to trigger a burst
        vblank = 1;
        // wait for the burst to finish
        wait (busy == 1);
        wait (busy == 0);
        vblank = 0;

        // let the final registered write pulse + counter settle (avoid tb race)
        repeat (3) @(posedge clk);
        if (writes != DEPTH) begin
            $display("FAIL: wrote %0d cells, expected %0d", writes, DEPTH);
            for (i = 0; i < DEPTH; i = i + 1)
                if (!seen[i]) $display("  missing addr %0d", i);
            $fatal(1);
        end

        // spot-check the heightmap contents via read port
        for (i = 0; i < DEPTH; i = i + 64) begin
            hm_re = 1; hm_raddr = i; @(posedge clk); @(posedge clk);
            if (hm_rdout !== expect_mem[i]) begin
                $display("READBACK MISMATCH addr=%0d got=%0d exp=%0d", i, hm_rdout, expect_mem[i]);
                $fatal(1);
            end
        end
        hm_re = 0;

        $display("PASS: bridge copied %0d cells, scaling and readback verified.", writes);
        $finish;
    end

    initial begin
        #2000000;
        $display("TIMEOUT"); $fatal(1);
    end
endmodule
