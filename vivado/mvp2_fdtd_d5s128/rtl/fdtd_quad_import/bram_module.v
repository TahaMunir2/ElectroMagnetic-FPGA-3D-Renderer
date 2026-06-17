`timescale 1ns/1ps

/**
 * BRAM Module - Field Storage for 2D FDTD Solver
 *
 * Owner: Yi
 *
 * Stores Ey, Ex, and Bz field values for a 2D FDTD grid.
 * Each field has two synchronous read ports and one synchronous write port.
 *
 * This gives the FDTD datapath six read address inputs total:
 *   - Ey read port 0
 *   - Ey read port 1
 *   - Ex read port 0
 *   - Ex read port 1
 *   - Bz read port 0
 *   - Bz read port 1
 *
 * The implementation uses replicated memories so each field can support two
 * simultaneous reads while keeping one write interface.
 */

module bram_module #(
    parameter DEPTH = 64,
    parameter WIDTH = 16,
    parameter ADDR_WIDTH = 6
)(
    input  wire clk,
    input  wire rst,

    // Ey read ports
    input  wire [ADDR_WIDTH-1:0] ey_rd_addr_0,
    output wire [WIDTH-1:0]      ey_rd_data_0,
    input  wire [ADDR_WIDTH-1:0] ey_rd_addr_1,
    output wire [WIDTH-1:0]      ey_rd_data_1,

    // Ex read ports
    input  wire [ADDR_WIDTH-1:0] ex_rd_addr_0,
    output wire [WIDTH-1:0]      ex_rd_data_0,
    input  wire [ADDR_WIDTH-1:0] ex_rd_addr_1,
    output wire [WIDTH-1:0]      ex_rd_data_1,

    // Bz read ports
    input  wire [ADDR_WIDTH-1:0] bz_rd_addr_0,
    output wire [WIDTH-1:0]      bz_rd_data_0,
    input  wire [ADDR_WIDTH-1:0] bz_rd_addr_1,
    output wire [WIDTH-1:0]      bz_rd_data_1,

    // Ey write port
    input  wire                  ey_we,
    input  wire [ADDR_WIDTH-1:0] ey_wr_addr,
    input  wire [WIDTH-1:0]      ey_wr_data,

    // Ex write port
    input  wire                  ex_we,
    input  wire [ADDR_WIDTH-1:0] ex_wr_addr,
    input  wire [WIDTH-1:0]      ex_wr_data,

    // Bz write port
    input  wire                  bz_we,
    input  wire [ADDR_WIDTH-1:0] bz_wr_addr,
    input  wire [WIDTH-1:0]      bz_wr_data
);

    (* ram_style = "block" *) reg [WIDTH-1:0] ey_mem_0 [0:DEPTH-1];
    (* ram_style = "block" *) reg [WIDTH-1:0] ey_mem_1 [0:DEPTH-1];
    (* ram_style = "block" *) reg [WIDTH-1:0] ex_mem_0 [0:DEPTH-1];
    (* ram_style = "block" *) reg [WIDTH-1:0] ex_mem_1 [0:DEPTH-1];
    (* ram_style = "block" *) reg [WIDTH-1:0] bz_mem_0 [0:DEPTH-1];
    (* ram_style = "block" *) reg [WIDTH-1:0] bz_mem_1 [0:DEPTH-1];

    // Block-RAM read registers (READ_FIRST, no reset -> BRAM-inferable) + the
    // write-first collision bypass moved to fabric. Behaviour and 1-cycle
    // latency are identical to the original inline-bypass version, but this
    // form infers block RAM instead of LUTRAM (needed at 128x128).
    reg [WIDTH-1:0] ey_rd0_b, ey_rd1_b, ex_rd0_b, ex_rd1_b, bz_rd0_b, bz_rd1_b;
    reg [WIDTH-1:0] ey_wd0, ey_wd1, ex_wd0, ex_wd1, bz_wd0, bz_wd1;
    reg             ey_by0, ey_by1, ex_by0, ex_by1, bz_by0, bz_by1;

    integer init_idx;
    initial begin
        for (init_idx = 0; init_idx < DEPTH; init_idx = init_idx + 1) begin
            ey_mem_0[init_idx] = {WIDTH{1'b0}};
            ey_mem_1[init_idx] = {WIDTH{1'b0}};
            ex_mem_0[init_idx] = {WIDTH{1'b0}};
            ex_mem_1[init_idx] = {WIDTH{1'b0}};
            bz_mem_0[init_idx] = {WIDTH{1'b0}};
            bz_mem_1[init_idx] = {WIDTH{1'b0}};
        end
    end

    // --- block RAM: replicated writes + READ_FIRST registered reads (no reset) ---
    always @(posedge clk) begin
        if (ey_we) begin ey_mem_0[ey_wr_addr] <= ey_wr_data; ey_mem_1[ey_wr_addr] <= ey_wr_data; end
        if (ex_we) begin ex_mem_0[ex_wr_addr] <= ex_wr_data; ex_mem_1[ex_wr_addr] <= ex_wr_data; end
        if (bz_we) begin bz_mem_0[bz_wr_addr] <= bz_wr_data; bz_mem_1[bz_wr_addr] <= bz_wr_data; end
        ey_rd0_b <= ey_mem_0[ey_rd_addr_0];
        ey_rd1_b <= ey_mem_1[ey_rd_addr_1];
        ex_rd0_b <= ex_mem_0[ex_rd_addr_0];
        ex_rd1_b <= ex_mem_1[ex_rd_addr_1];
        bz_rd0_b <= bz_mem_0[bz_rd_addr_0];
        bz_rd1_b <= bz_mem_1[bz_rd_addr_1];
    end

    // --- fabric write-first bypass (registered to match the 1-cycle read) ---
    always @(posedge clk) begin
        if (rst) begin
            ey_by0 <= 1'b0; ey_by1 <= 1'b0; ex_by0 <= 1'b0;
            ex_by1 <= 1'b0; bz_by0 <= 1'b0; bz_by1 <= 1'b0;
        end else begin
            ey_by0 <= ey_we && (ey_rd_addr_0 == ey_wr_addr);
            ey_by1 <= ey_we && (ey_rd_addr_1 == ey_wr_addr);
            ex_by0 <= ex_we && (ex_rd_addr_0 == ex_wr_addr);
            ex_by1 <= ex_we && (ex_rd_addr_1 == ex_wr_addr);
            bz_by0 <= bz_we && (bz_rd_addr_0 == bz_wr_addr);
            bz_by1 <= bz_we && (bz_rd_addr_1 == bz_wr_addr);
        end
        ey_wd0 <= ey_wr_data; ey_wd1 <= ey_wr_data;
        ex_wd0 <= ex_wr_data; ex_wd1 <= ex_wr_data;
        bz_wd0 <= bz_wr_data; bz_wd1 <= bz_wr_data;
    end

    assign ey_rd_data_0 = ey_by0 ? ey_wd0 : ey_rd0_b;
    assign ey_rd_data_1 = ey_by1 ? ey_wd1 : ey_rd1_b;
    assign ex_rd_data_0 = ex_by0 ? ex_wd0 : ex_rd0_b;
    assign ex_rd_data_1 = ex_by1 ? ex_wd1 : ex_rd1_b;
    assign bz_rd_data_0 = bz_by0 ? bz_wd0 : bz_rd0_b;
    assign bz_rd_data_1 = bz_by1 ? bz_wd1 : bz_rd1_b;

endmodule
