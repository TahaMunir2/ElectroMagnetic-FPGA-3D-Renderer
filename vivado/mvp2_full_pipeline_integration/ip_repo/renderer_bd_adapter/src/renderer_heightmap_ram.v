`timescale 1ns/1ps

module renderer_heightmap_ram #(
    parameter ADDR_WIDTH = 12,
    parameter DATA_WIDTH = 16
)(
    input  wire                       clk,

    input  wire                       we,
    input  wire [ADDR_WIDTH-1:0]      waddr,
    input  wire [DATA_WIDTH-1:0]      wdata,

    input  wire                       re,
    input  wire [ADDR_WIDTH-1:0]      raddr,
    output reg  signed [DATA_WIDTH-1:0] rdata
);

    localparam DEPTH = (1 << ADDR_WIDTH);

    (* ram_style = "block" *)
    reg signed [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    always @(posedge clk) begin
        if (we) begin
            mem[waddr] <= wdata;
        end

        if (re) begin
            rdata <= mem[raddr];
        end
    end

endmodule
