`timescale 1ns/1ps
// ============================================================================
//  heightmap_bram_d5_dualread.sv
//
//  One writable 64x64 heightmap copy with two clk_core read ports.
//  Port A is write-or-read; port B is read-only. The renderer only writes during
//  the guarded vblank update window, so active rendering sees two read ports.
//  Stored height is 8-bit, repacked to the renderer's 16-bit fixed-point format.
// ============================================================================
module heightmap_bram_d5_dualread #(
    parameter int ADDR_W = 12,
    parameter int DATA_W = 16
)(
    input  wire                       clk,

    input  wire                       we,
    input  wire [ADDR_W-1:0]          waddr,
    input  wire signed [DATA_W-1:0]   wdata,

    input  wire [ADDR_W-1:0]          addr_a,
    input  wire                       re_a,
    output wire signed [DATA_W-1:0]   dout_a,

    input  wire [ADDR_W-1:0]          addr_b,
    input  wire                       re_b,
    output wire signed [DATA_W-1:0]   dout_b
);
    localparam int DEPTH = 1 << ADDR_W;

    wire [7:0] dout_a8;
    wire [7:0] dout_b8;
    wire [ADDR_W-1:0] port_a_addr = we ? waddr : addr_a;

    assign dout_a = {dout_a8, {(DATA_W-8){1'b0}}};
    assign dout_b = {dout_b8, {(DATA_W-8){1'b0}}};

    xpm_memory_tdpram #(
        .ADDR_WIDTH_A(ADDR_W),
        .ADDR_WIDTH_B(ADDR_W),
        .AUTO_SLEEP_TIME(0),
        .BYTE_WRITE_WIDTH_A(8),
        .BYTE_WRITE_WIDTH_B(8),
        .CLOCKING_MODE("common_clock"),
        .ECC_MODE("no_ecc"),
        .MEMORY_INIT_FILE("none"),
        .MEMORY_INIT_PARAM("0"),
        .MEMORY_OPTIMIZATION("true"),
        .MEMORY_PRIMITIVE("block"),
        .MEMORY_SIZE(DEPTH * 8),
        .MESSAGE_CONTROL(0),
        .READ_DATA_WIDTH_A(8),
        .READ_DATA_WIDTH_B(8),
        .READ_LATENCY_A(1),
        .READ_LATENCY_B(1),
        .READ_RESET_VALUE_A("0"),
        .READ_RESET_VALUE_B("0"),
        .RST_MODE_A("SYNC"),
        .RST_MODE_B("SYNC"),
        .USE_EMBEDDED_CONSTRAINT(0),
        .USE_MEM_INIT(1),
        .WAKEUP_TIME("disable_sleep"),
        .WRITE_DATA_WIDTH_A(8),
        .WRITE_DATA_WIDTH_B(8),
        .WRITE_MODE_A("no_change"),
        .WRITE_MODE_B("no_change")
    ) u_mem (
        .clka(clk),
        .clkb(clk),
        .ena(we | re_a),
        .enb(re_b),
        .addra(port_a_addr),
        .addrb(addr_b),
        .dina(wdata[DATA_W-1 -: 8]),
        .dinb(8'd0),
        .wea(we),
        .web(1'b0),
        .douta(dout_a8),
        .doutb(dout_b8),
        .regcea(1'b1),
        .regceb(1'b1),
        .rsta(1'b0),
        .rstb(1'b0),
        .sleep(1'b0),
        .injectsbiterra(1'b0),
        .injectsbiterrb(1'b0),
        .injectdbiterra(1'b0),
        .injectdbiterrb(1'b0),
        .sbiterra(),
        .sbiterrb(),
        .dbiterra(),
        .dbiterrb()
    );
endmodule
