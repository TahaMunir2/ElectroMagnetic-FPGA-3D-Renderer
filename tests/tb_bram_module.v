`timescale 1ns/1ps

module tb_bram_module;
    localparam DEPTH = 64;
    localparam WIDTH = 16;
    localparam ADDR_WIDTH = 6;

    reg clk = 1'b0;
    reg rst = 1'b1;

    reg                  we_a = 1'b0;
    reg [ADDR_WIDTH-1:0] addr_a = {ADDR_WIDTH{1'b0}};
    reg [WIDTH-1:0]      din_a = {WIDTH{1'b0}};
    wire [WIDTH-1:0]     dout_a;

    reg                  we_b = 1'b0;
    reg [ADDR_WIDTH-1:0] addr_b = {ADDR_WIDTH{1'b0}};
    reg [WIDTH-1:0]      din_b = {WIDTH{1'b0}};
    wire [WIDTH-1:0]     dout_b;

    bram_module #(
        .DEPTH(DEPTH),
        .WIDTH(WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .we_a(we_a),
        .addr_a(addr_a),
        .din_a(din_a),
        .dout_a(dout_a),
        .we_b(we_b),
        .addr_b(addr_b),
        .din_b(din_b),
        .dout_b(dout_b)
    );

    always #5 clk = ~clk;

    task check_word;
        input [WIDTH-1:0] actual;
        input [WIDTH-1:0] expected;
        input [8*32-1:0] label;
        begin
            if (actual !== expected) begin
                $display("BRAM_FAIL %0s expected=%h actual=%h", label, expected, actual);
                $finish;
            end
        end
    endtask

    initial begin
        $dumpfile("build/bram_module.vcd");
        $dumpvars(0, tb_bram_module);

        repeat (2) @(posedge clk);
        rst = 1'b0;

        @(negedge clk);
        addr_a = 6'd3;
        din_a = 16'h1234;
        we_a = 1'b1;
        addr_b = 6'd5;
        din_b = 16'hcafe;
        we_b = 1'b1;

        @(posedge clk);
        #1;
        check_word(dout_a, 16'h1234, "ey write-first");
        check_word(dout_b, 16'hcafe, "bz write-first");

        @(negedge clk);
        we_a = 1'b0;
        we_b = 1'b0;
        din_a = 16'h0000;
        din_b = 16'h0000;

        @(posedge clk);
        #1;
        check_word(dout_a, 16'h1234, "ey readback");
        check_word(dout_b, 16'hcafe, "bz readback");

        @(negedge clk);
        addr_a = 6'd4;
        addr_b = 6'd6;

        @(posedge clk);
        #1;
        check_word(dout_a, 16'h0000, "ey init zero");
        check_word(dout_b, 16'h0000, "bz init zero");

        $display("BRAM_PASS");
        $finish;
    end
endmodule
