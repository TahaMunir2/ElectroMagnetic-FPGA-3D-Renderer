`timescale 1ns/1ps

module tb_cordic_generator;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg [15:0] phase_in = 16'h0000;
    reg phase_valid = 1'b0;

    wire [15:0] sin_out;
    wire [15:0] cos_out;
    wire out_valid;

    integer sample_count = 0;
    reg fail = 1'b0;

    cordic_generator dut (
        .clk(clk),
        .rst(rst),
        .phase_in(phase_in),
        .phase_valid(phase_valid),
        .sin_out(sin_out),
        .cos_out(cos_out),
        .out_valid(out_valid)
    );

    always #5 clk = ~clk;

    function integer abs_int;
        input integer value;
        begin
            abs_int = (value < 0) ? -value : value;
        end
    endfunction

    task check_close;
        input signed [15:0] actual;
        input signed [15:0] expected;
        input integer tolerance;
        input [8*32-1:0] label;
        integer diff;
        begin
            diff = actual - expected;
            if (abs_int(diff) > tolerance) begin
                $display("test failed: %0s expected=%0d actual=%0d", label, expected, actual);
                fail = 1'b1;
            end
        end
    endtask

    task check_sample;
        input integer sample;
        begin
            case (sample)
                1: begin
                    check_close($signed(sin_out), 16'sd8192, 16, "quarter sin");
                    check_close($signed(cos_out), 16'sd0, 16, "quarter cos");
                    if (!fail) $display("test 1 passed: quarter turn sin=%0d cos=%0d", $signed(sin_out), $signed(cos_out));
                end
                2: begin
                    check_close($signed(sin_out), 16'sd0, 16, "half sin");
                    check_close($signed(cos_out), -16'sd8192, 16, "half cos");
                    if (!fail) $display("test 2 passed: half turn sin=%0d cos=%0d", $signed(sin_out), $signed(cos_out));
                end
                3: begin
                    check_close($signed(sin_out), -16'sd8192, 16, "three_quarter sin");
                    check_close($signed(cos_out), 16'sd0, 16, "three_quarter cos");
                    if (!fail) $display("test 3 passed: three quarter turn sin=%0d cos=%0d", $signed(sin_out), $signed(cos_out));
                end
                4: begin
                    check_close($signed(sin_out), 16'sd0, 16, "full sin");
                    check_close($signed(cos_out), 16'sd8192, 16, "full cos");
                    if (!fail) $display("test 4 passed: full turn sin=%0d cos=%0d", $signed(sin_out), $signed(cos_out));
                end
            endcase
        end
    endtask

    always @(posedge clk) begin
        if (!rst && out_valid) begin
            sample_count = sample_count + 1;
            check_sample(sample_count);
        end
    end

    initial begin
        repeat (10) @(posedge clk);
        rst = 1'b0;

        // Send absolute phase samples continuously:
        // quarter, half, three-quarter, full/zero.
        @(negedge clk);
        phase_in = 16'h4000;
        phase_valid = 1'b1;

        @(negedge clk);
        phase_in = 16'h8000;
        phase_valid = 1'b1;

        @(negedge clk);
        phase_in = 16'hc000;
        phase_valid = 1'b1;

        @(negedge clk);
        phase_in = 16'h0000;
        phase_valid = 1'b1;

        @(negedge clk);
        phase_valid = 1'b0;

        repeat (40) @(posedge clk);

        if (sample_count != 4) begin
            $display("test failed: expected 4 samples, got %0d", sample_count);
            $finish;
        end

        if (fail) begin
            $finish;
        end

        $display("all 4 tests passed");
        $finish;
    end
endmodule
