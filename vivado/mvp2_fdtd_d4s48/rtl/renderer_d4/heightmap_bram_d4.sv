`timescale 1ns/1ps
// ============================================================================
//  heightmap_bram_d4.sv
//  Dual-clock writable heightmap copy for the D4S48 live-FDTD integration.
//
//   - write port @ wr_clk (clk_pix, 25 MHz): the bridge writes a 16-bit height;
//     only the TOP 8 bits are stored. 8-bit storage => 4096x8 packs into ONE
//     RAMB36 per copy, so 48 marcher + 2 normal = 50 copies fit alongside the
//     128x128 FDTD (~50 + ~50 of 140).
//   - read port @ rd_clk (clk_core, 100 MHz): returns the stored 8 bits packed
//     back into the renderer's 16-bit height word ({top8, 0}), with 1-cycle
//     latency to MATCH Cyril's read-only heightmap_bram so marcher4 timing is
//     unchanged.
//
//  Simple-dual-port, independent clocks. The write is broadcast (identical) to
//  all 50 copies by the wrapper; each copy has its own marcher/normal read addr.
// ============================================================================
module heightmap_bram_d4 #(
    parameter int ADDR_W = 12,
    parameter int DATA_W = 16
)(
    input  wire                     wr_clk,
    input  wire                     we,
    input  wire [ADDR_W-1:0]        waddr,
    input  wire signed [DATA_W-1:0] wdata,

    input  wire                     rd_clk,
    input  wire [ADDR_W-1:0]        addr,
    input  wire                     re,
    output reg  signed [DATA_W-1:0] dout
);
    localparam int DEPTH = 1 << ADDR_W;
    (* ram_style = "block" *) reg [7:0] mem [0:DEPTH-1];
    integer i;
    initial for (i = 0; i < DEPTH; i = i + 1) mem[i] = 8'd0;

    always @(posedge wr_clk)
        if (we) mem[waddr] <= wdata[DATA_W-1 -: 8];            // store top 8 bits

    always @(posedge rd_clk)
        if (re) dout <= {mem[addr], {(DATA_W-8){1'b0}}};       // 1-cyc read, repack to 16-bit
endmodule
