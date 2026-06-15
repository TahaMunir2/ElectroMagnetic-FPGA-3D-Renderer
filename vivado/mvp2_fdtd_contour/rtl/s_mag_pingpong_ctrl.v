`timescale 1ns/1ps

// Ping-pong controller for the s_mag BRAM pair.
//
// field_magnitude_bd_adapter always writes to the "inactive" buffer.
// On mag_done, the buffers swap: the freshly written buffer becomes the
// "read" buffer and the stale one becomes the next write target.
//
// read_sel: 0 = external reader should use bram_a port B
//           1 = external reader should use bram_b port B
//
// Initially write_sel=0 (write to A), read_sel=1 (read from B - empty until
// first swap). After first swap: write_sel=1, read_sel=0 (read first frame
// from A while writing second frame to B).

module s_mag_pingpong_ctrl #(
    parameter ADDR_WIDTH = 12,
    parameter DATA_WIDTH = 16
)(
    input  wire                   clk,
    input  wire                   rst,

    // Write side — from field_magnitude_bd_adapter
    input  wire [ADDR_WIDTH-1:0]  s_mag_addra,
    input  wire                   s_mag_ena,
    input  wire [0:0]             s_mag_wea,
    input  wire [DATA_WIDTH-1:0]  s_mag_dina,
    input  wire                   mag_done,

    // BRAM A port A (write path)
    output wire [ADDR_WIDTH-1:0]  bram_a_addra,
    output wire                   bram_a_ena,
    output wire [0:0]             bram_a_wea,
    output wire [DATA_WIDTH-1:0]  bram_a_dina,

    // BRAM B port A (write path)
    output wire [ADDR_WIDTH-1:0]  bram_b_addra,
    output wire                   bram_b_ena,
    output wire [0:0]             bram_b_wea,
    output wire [DATA_WIDTH-1:0]  bram_b_dina,

    // Status
    output reg                    read_sel,      // which buffer the reader should use
    output reg                    frame_ready    // 1-cycle pulse when new frame is ready
);

    reg write_sel;

    always @(posedge clk) begin
        if (rst) begin
            write_sel   <= 1'b0;
            read_sel    <= 1'b1;
            frame_ready <= 1'b0;
        end else begin
            frame_ready <= 1'b0;
            if (mag_done) begin
                write_sel   <= ~write_sel;
                read_sel    <= ~read_sel;
                frame_ready <= 1'b1;
            end
        end
    end

    // Route writes to the active write buffer; the other gets no writes
    assign bram_a_addra = s_mag_addra;
    assign bram_a_ena   = s_mag_ena  & ~write_sel;
    assign bram_a_wea   = s_mag_wea  & {1{~write_sel}};
    assign bram_a_dina  = s_mag_dina;

    assign bram_b_addra = s_mag_addra;
    assign bram_b_ena   = s_mag_ena  & write_sel;
    assign bram_b_wea   = s_mag_wea  & {1{write_sel}};
    assign bram_b_dina  = s_mag_dina;

endmodule
