`timescale 1ns/1ps
// =============================================================================
//  heightmap_bram_rw.sv
//
//  Writable replacement for the read-only mock `heightmap_bram` used by the
//  D1S48 renderer.  Simple-dual-port (SDP):
//
//    Write port : we / waddr / wdata   <- driven by s_mag_to_heightmap_bridge
//    Read  port : addr / re / dout     -> driven by the renderer ray_unit
//
//  The READ port (clk/addr/re/dout) is pin-compatible with the original
//  `heightmap_bram` so the ray_unit wiring inside d1s48_renderer_core_axi is
//  unchanged — only the write port is new.
//
//  Single clock domain (clk_pix).  4096 x 16 infers 2 x RAMB36E1 per instance.
//  Writes are gated to vertical blanking by the bridge, so the read port is
//  idle during writes (no read/write address collision).
// =============================================================================
module heightmap_bram_rw #(
    parameter int ADDR_W = 12,
    parameter int DATA_W = 16
)(
    input  logic                     clk,
    // write port (bridge)
    input  logic                     we,
    input  logic [ADDR_W-1:0]        waddr,
    input  logic signed [DATA_W-1:0] wdata,
    // read port (renderer) — identical to the original read-only heightmap_bram
    input  logic [ADDR_W-1:0]        addr,
    input  logic                     re,
    output logic signed [DATA_W-1:0] dout
);
    localparam int DEPTH = 1 << ADDR_W;

    (* ram_style = "block" *)
    logic signed [DATA_W-1:0] mem [0:DEPTH-1];

    // Start flat so the first rendered frames (before the bridge has copied a
    // wave in) show a flat plane rather than X's in simulation.
    initial begin
        for (int i = 0; i < DEPTH; i++)
            mem[i] = '0;
    end

    always_ff @(posedge clk) begin
        if (we)
            mem[waddr] <= wdata;
    end

    always_ff @(posedge clk) begin
        if (re)
            dout <= mem[addr];
    end
endmodule
