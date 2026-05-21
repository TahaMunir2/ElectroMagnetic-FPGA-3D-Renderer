`timescale 1ns/1ps

module tb_cordic_generator;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg [15:0] phase_in = 16'd0;
    reg phase_valid = 1'b0;

    wire [15:0] sin_out;
    wire [15:0] cos_out;
    wire out_valid;

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
                $display("CORDIC_FAIL %0s expected=%0d actual=%0d diff=%0d",
                         label, expected, actual, diff);
                $finish;
            end
        end
    endtask

    task drive_phase_step;
        input [15:0] step;
        input signed [15:0] expected_sin;
        input signed [15:0] expected_cos;
        input [8*32-1:0] label;
        begin
            @(negedge clk);
            phase_in = step;
            phase_valid = 1'b1;

            @(negedge clk);
            phase_valid = 1'b0;

            wait (out_valid === 1'b1);
            #1;
            check_close(sin_out, expected_sin, 16, {label, " sin"});
            check_close(cos_out, expected_cos, 16, {label, " cos"});
            $display("CORDIC_SAMPLE %0s sin=%0d cos=%0d", label, $signed(sin_out), $signed(cos_out));
        end
    endtask

    initial begin
        $dumpfile("build/cordic_generator.vcd");
        $dumpvars(0, tb_cordic_generator);

        repeat (2) @(posedge clk);
        rst = 1'b0;

        drive_phase_step(16'h4000, 16'sd8192, 16'sd0, "quarter");
        drive_phase_step(16'h4000, 16'sd0, -16'sd8192, "half");
        drive_phase_step(16'h4000, -16'sd8192, 16'sd0, "three_quarter");
        drive_phase_step(16'h4000, 16'sd0, 16'sd8192, "full");

        $display("CORDIC_PASS");
        $finish;
    end
endmodule
