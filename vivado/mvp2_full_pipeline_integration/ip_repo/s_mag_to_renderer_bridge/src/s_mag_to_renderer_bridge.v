`timescale 1ns/1ps

module s_mag_to_renderer_bridge #(
    parameter SRC_CELLS = 192,
    parameter DST_CELLS = 64,
    parameter SRC_ADDR_WIDTH = 16,
    parameter DST_ADDR_WIDTH = 12,
    parameter DATA_WIDTH = 16
)(
    input  wire                       clk,
    input  wire                       rst,
    input  wire                       start,

    output reg  [SRC_ADDR_WIDTH-1:0]  s_mag_addr,
    output wire                       s_mag_en,
    output wire [0:0]                 s_mag_we,
    output wire [DATA_WIDTH-1:0]      s_mag_din,
    input  wire [DATA_WIDTH-1:0]      s_mag_dout,

    output reg                        heightmap_we,
    output reg  [DST_ADDR_WIDTH-1:0]  heightmap_waddr,
    output reg  [DATA_WIDTH-1:0]      heightmap_wdata,

    output reg                        busy,
    output reg                        done,
    output reg                        ready
);

    localparam [1:0] ST_IDLE  = 2'd0;
    localparam [1:0] ST_ISSUE = 2'd1;
    localparam [1:0] ST_WAIT  = 2'd2;
    localparam [1:0] ST_WRITE = 2'd3;

    localparam [DST_ADDR_WIDTH-1:0] LAST_DST_ADDR =
        (DST_CELLS * DST_CELLS) - 1;

    reg [1:0] state;
    reg [DST_ADDR_WIDTH-1:0] dst_addr;
    reg [DST_ADDR_WIDTH-1:0] issued_dst_addr;

    assign s_mag_en  = (state == ST_WAIT);
    assign s_mag_we  = 1'b0;
    assign s_mag_din = {DATA_WIDTH{1'b0}};

    function [SRC_ADDR_WIDTH-1:0] source_addr_for_dst;
        input [DST_ADDR_WIDTH-1:0] dst;
        reg [7:0] dst_x;
        reg [7:0] dst_y;
        reg [15:0] src_x;
        reg [15:0] src_y;
        begin
            dst_x = dst[5:0];
            dst_y = dst[11:6];
            src_x = (dst_x * 3) + 1;
            src_y = (dst_y * 3) + 1;
            source_addr_for_dst = (src_y * SRC_CELLS) + src_x;
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            state            <= ST_IDLE;
            dst_addr         <= {DST_ADDR_WIDTH{1'b0}};
            issued_dst_addr  <= {DST_ADDR_WIDTH{1'b0}};
            s_mag_addr       <= {SRC_ADDR_WIDTH{1'b0}};
            heightmap_we     <= 1'b0;
            heightmap_waddr  <= {DST_ADDR_WIDTH{1'b0}};
            heightmap_wdata  <= {DATA_WIDTH{1'b0}};
            busy             <= 1'b0;
            done             <= 1'b0;
            ready            <= 1'b0;
        end else begin
            heightmap_we <= 1'b0;
            done         <= 1'b0;

            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        dst_addr        <= {DST_ADDR_WIDTH{1'b0}};
                        issued_dst_addr <= {DST_ADDR_WIDTH{1'b0}};
                        ready           <= 1'b0;
                        busy            <= 1'b1;
                        state           <= ST_ISSUE;
                    end
                end

                ST_ISSUE: begin
                    s_mag_addr      <= source_addr_for_dst(dst_addr);
                    issued_dst_addr <= dst_addr;
                    busy            <= 1'b1;
                    state           <= ST_WAIT;
                end

                ST_WAIT: begin
                    busy  <= 1'b1;
                    state <= ST_WRITE;
                end

                ST_WRITE: begin
                    heightmap_we    <= 1'b1;
                    heightmap_waddr <= issued_dst_addr;
                    heightmap_wdata <= s_mag_dout;
                    busy            <= 1'b1;

                    if (issued_dst_addr == LAST_DST_ADDR) begin
                        busy  <= 1'b0;
                        done  <= 1'b1;
                        ready <= 1'b1;
                        state <= ST_IDLE;
                    end else begin
                        dst_addr <= issued_dst_addr + {{(DST_ADDR_WIDTH-1){1'b0}}, 1'b1};
                        state    <= ST_ISSUE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
