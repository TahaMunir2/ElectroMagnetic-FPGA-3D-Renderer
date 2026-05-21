`timescale 1ns/1ps

/**
 * BRAM Module - Dual Port RAM for FDTD Solver
 *
 * Owner: Yi
 *
 * Stores Ey and Bz field values for 64-cell 1D FDTD grid
 * Q3.13 fixed-point precision (16-bit words)
 */

module bram_module #(
    parameter DEPTH = 64,
    parameter WIDTH = 16,
    parameter ADDR_WIDTH = 6
)(
    // Clock and Reset
    input  wire clk,
    input  wire rst,

    // Port A - Ey data
    input  wire                   we_a,
    input  wire [ADDR_WIDTH-1:0]  addr_a,
    input  wire [WIDTH-1:0]       din_a,
    output wire [WIDTH-1:0]       dout_a,

    // Port B - Bz data
    input  wire                   we_b,
    input  wire [ADDR_WIDTH-1:0]  addr_b,
    input  wire [WIDTH-1:0]       din_b,
    output wire [WIDTH-1:0]       dout_b
);

    (* ram_style = "block" *) reg [WIDTH-1:0] ey_mem [0:DEPTH-1];
    (* ram_style = "block" *) reg [WIDTH-1:0] bz_mem [0:DEPTH-1];

    reg [WIDTH-1:0] dout_a_reg;
    reg [WIDTH-1:0] dout_b_reg;

    integer init_idx;

    initial begin
        dout_a_reg = {WIDTH{1'b0}};
        dout_b_reg = {WIDTH{1'b0}};

        for (init_idx = 0; init_idx < DEPTH; init_idx = init_idx + 1) begin
            ey_mem[init_idx] = {WIDTH{1'b0}};
            bz_mem[init_idx] = {WIDTH{1'b0}};
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            dout_a_reg <= {WIDTH{1'b0}};
            dout_b_reg <= {WIDTH{1'b0}};
        end else begin
            if (we_a) begin
                ey_mem[addr_a] <= din_a;
                dout_a_reg <= din_a;
            end else begin
                dout_a_reg <= ey_mem[addr_a];
            end

            if (we_b) begin
                bz_mem[addr_b] <= din_b;
                dout_b_reg <= din_b;
            end else begin
                dout_b_reg <= bz_mem[addr_b];
            end
        end
    end

    assign dout_a = dout_a_reg;
    assign dout_b = dout_b_reg;

endmodule
