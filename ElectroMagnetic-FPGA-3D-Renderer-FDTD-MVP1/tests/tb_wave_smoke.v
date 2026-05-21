`timescale 1ns/1ps

module wave_smoke_dut (
    input  wire       clk,
    input  wire       rst,
    input  wire       enable,
    output reg  [3:0] count,
    output reg  [1:0] phase,
    output wire       pulse
);
    assign pulse = enable && (count == 4'd8);

    always @(posedge clk) begin
        if (rst) begin
            count <= 4'd0;
            phase <= 2'd0;
        end else if (enable) begin
            count <= count + 4'd1;
            phase <= count[3:2];
        end
    end
endmodule

module tb_wave_smoke;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg enable = 1'b0;

    wire [3:0] count;
    wire [1:0] phase;
    wire       pulse;

    wave_smoke_dut dut (
        .clk(clk),
        .rst(rst),
        .enable(enable),
        .count(count),
        .phase(phase),
        .pulse(pulse)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("build/wave_smoke.vcd");
        $dumpvars(0, tb_wave_smoke);

        $display("time=%0t reset asserted", $time);
        #20;
        rst = 1'b0;
        enable = 1'b1;
        $display("time=%0t counter enabled", $time);

        repeat (16) @(posedge clk);
        #1;

        if (count !== 4'd0) begin
            $display("WAVE_SMOKE_FAIL expected wrapped count=0 actual=%0d", count);
            $finish;
        end

        $display("WAVE_SMOKE_PASS final_count=%0d phase=%0d pulse=%b", count, phase, pulse);
        $finish;
    end
endmodule
