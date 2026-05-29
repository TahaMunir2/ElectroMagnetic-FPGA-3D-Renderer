`timescale 1ns/1ps

// True-dual-port 16-bit x 4096 synchronous block RAM for 64x64 FDTD fields.
// Parameters are intentionally hardcoded — no overridable parameter — so that
// the Vivado IP wrapper cannot substitute stale XCI values and inflate BRAM use.
// 1-cycle read latency, read-first. Synthesises to RAMB36E1 on Zynq-7000.
module field_bram (
    input  wire         clka,
    input  wire         ena,
    input  wire [11:0]  addra,
    input  wire [0:0]   wea,
    input  wire [15:0]  dina,
    output reg  [15:0]  douta,

    input  wire         clkb,
    input  wire         enb,
    input  wire [11:0]  addrb,
    input  wire [0:0]   web,
    input  wire [15:0]  dinb,
    output reg  [15:0]  doutb
);
    (* ram_style = "block" *) reg [15:0] mem [0:4095];

    always @(posedge clka) begin
        if (ena) begin
            douta <= mem[addra];
            if (wea) mem[addra] <= dina;
        end
    end

    always @(posedge clkb) begin
        if (enb) begin
            doutb <= mem[addrb];
            if (web) mem[addrb] <= dinb;
        end
    end
endmodule
