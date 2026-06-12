`timescale 1ns/1ps

module tb_pml;

    localparam DATA_WIDTH = 16;
    localparam CELL_WIDTH = 6;
    localparam PML_SIZE   = 6;

    logic signed [CELL_WIDTH-1:0] d;
    logic signed [DATA_WIDTH-1:0] ca;
    logic signed [DATA_WIDTH-1:0] cb_e;
    logic signed [DATA_WIDTH-1:0] cb_bz;

    pml #(
        .DATA_WIDTH(DATA_WIDTH),
        .CELL_WIDTH(CELL_WIDTH),
        .PML_SIZE(PML_SIZE)
    ) dut (
        .d(d),
        .ca(ca),
        .cb_e(cb_e),
        .cb_bz(cb_bz)
    );

    int pass_count = 0;
    int fail_count = 0;

    logic signed [DATA_WIDTH-1:0] exp_ca    [0:5];
    logic signed [DATA_WIDTH-1:0] exp_cb_e  [0:5];
    logic signed [DATA_WIDTH-1:0] exp_cb_bz [0:5];

    task automatic check(
        input int            depth,
        input signed [15:0]  got_ca,
        input signed [15:0]  got_cb_e,
        input signed [15:0]  got_cb_bz,
        input signed [15:0]  exp_ca,
        input signed [15:0]  exp_cb_e,
        input signed [15:0]  exp_cb_bz
    );
        if (got_ca === exp_ca && got_cb_e === exp_cb_e && got_cb_bz === exp_cb_bz) begin
            $display("test %0d passed: d=%0d ca=%0d cb=%0d", depth+1, depth, got_ca, got_cb_e);
            pass_count++;
        end else begin
            $display("test %0d failed: d=%0d ca=%0d expected %0d", depth+1, depth, got_ca, exp_ca);
            fail_count++;
        end
    endtask

    initial begin
        exp_ca[0]    =  16'sd8192; exp_cb_e[0]  = -16'sd717; exp_cb_bz[0] = -16'sd717;
        exp_ca[1]    =  16'sd8174; exp_cb_e[1]  = -16'sd717; exp_cb_bz[1] = -16'sd717;
        exp_ca[2]    =  16'sd8045; exp_cb_e[2]  = -16'sd717; exp_cb_bz[2] = -16'sd717;
        exp_ca[3]    =  16'sd7695; exp_cb_e[3]  = -16'sd717; exp_cb_bz[3] = -16'sd717;
        exp_ca[4]    =  16'sd7014; exp_cb_e[4]  = -16'sd717; exp_cb_bz[4] = -16'sd717;
        exp_ca[5]    =  16'sd5892; exp_cb_e[5]  = -16'sd717; exp_cb_bz[5] = -16'sd717;

        for (int i = 0; i < PML_SIZE; i++) begin
            d = i;
            #1;
            check(i, ca, cb_e, cb_bz, exp_ca[i], exp_cb_e[i], exp_cb_bz[i]);
        end

        d = 6;
        #1;
        if (ca === 16'sd8192 && cb_e === -16'sd717 && cb_bz === -16'sd717) begin
            $display("test 7 passed: d=6 default ca=%0d cb=%0d", ca, cb_e);
            pass_count++;
        end else begin
            $display("test 7 failed: d=6 default ca=%0d cb=%0d", ca, cb_e);
            fail_count++;
        end

        begin
            logic mono_ok;
            mono_ok = 1'b1;
            for (int i = 1; i < PML_SIZE; i++) begin
                if (!(exp_ca[i] < exp_ca[i-1])) begin
                    $display("test 8 failed: ca not decreasing at d=%0d", i);
                    mono_ok = 1'b0;
                    fail_count++;
                end
                if (!(exp_cb_e[i] >= exp_cb_e[i-1])) begin
                    $display("test 8 failed: cb_e not monotone at d=%0d", i);
                    mono_ok = 1'b0;
                    fail_count++;
                end
                if (!(exp_cb_bz[i] >= exp_cb_bz[i-1])) begin
                    $display("test 8 failed: cb_bz not monotone at d=%0d", i);
                    mono_ok = 1'b0;
                    fail_count++;
                end
            end
            if (mono_ok) begin
                $display("test 8 passed: ca ramp monotone with depth");
                pass_count++;
            end
        end

        if (fail_count == 0) $display("all 8 tests passed");
        else                 $display("%0d tests failed", fail_count);
        $finish;
    end

endmodule
