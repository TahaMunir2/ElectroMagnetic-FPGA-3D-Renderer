`timescale 1ns/1ps

// Simple-dual-port 16-bit x 4096 synchronous block RAM for 64x64 magnitude buffers.
// Parameters hardcoded — no overridable parameter — to prevent Vivado IP wrapper
// from substituting stale XCI values.
// 1-cycle read latency on port B. Synthesises to RAMB36E1 on Zynq-7000.
module smag_bram (
    input  wire         clka,
    input  wire         ena,
    input  wire [11:0]  addra,
    input  wire [0:0]   wea,
    input  wire [15:0]  dina,

    input  wire         clkb,
    input  wire         enb,
    input  wire [11:0]  addrb,
    output reg  [15:0]  doutb
);
    (* ram_style = "block" *) reg [15:0] mem [0:4095];

    always @(posedge clka) begin
        if (ena && wea) mem[addra] <= dina;
    end

    always @(posedge clkb) begin
        if (enb) doutb <= mem[addrb];
    end
endmodule
