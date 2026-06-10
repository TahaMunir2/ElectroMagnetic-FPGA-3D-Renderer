`timescale 1ns/1ps
// =============================================================================
//  field_magnitude_quad.v
//
//  Magnitude scanner for the quad-lane core. Identical |E|/|S|/signed-Ey
//  compute and 3-stage pipeline as field_magnitude_bd_adapter, but instead of
//  muxing per-field BRAM ports it drives the quad core's unified read-back
//  interface (mag_addr/mag_active -> mag_ey/mag_ex/mag_bz, 1-cycle latency).
//
//  On a `start` pulse it sweeps all 4096 cells and writes the per-cell value to
//  the s_mag write port (to the ping-pong controller).
//
//  mag_mode: 0 = |E| (rectified), 1 = |S| (Poynting), 2 = raw signed Ey (wave).
// =============================================================================
module field_magnitude_quad #(
    parameter CELLS = 64,
    parameter CELL_WIDTH = 6,
    parameter DATA_WIDTH = 16
)(
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire [1:0] mag_mode,

    output wire busy,
    output wire done,

    // quad-core field read-back interface
    output wire [2*CELL_WIDTH-1:0] mag_addr,
    output wire                    mag_active,
    input  wire signed [DATA_WIDTH-1:0] mag_ey,
    input  wire signed [DATA_WIDTH-1:0] mag_ex,
    input  wire signed [DATA_WIDTH-1:0] mag_bz,

    // s_mag write port (to s_mag_pingpong_ctrl)
    output wire [2*CELL_WIDTH-1:0] s_mag_addra,
    output wire                    s_mag_ena,
    output wire [0:0]              s_mag_wea,
    output wire [DATA_WIDTH-1:0]   s_mag_dina
);
    localparam integer GRID_SIZE = CELLS * CELLS;
    localparam [2*CELL_WIDTH-1:0] LAST_ADDR = GRID_SIZE - 1;
    localparam integer MAG_PRODUCT_SHIFT = 13;

    reg [2*CELL_WIDTH-1:0] mag_rd_addr;
    reg [2*CELL_WIDTH-1:0] mag_wr_addr;
    reg [DATA_WIDTH-1:0]   mag_wr_data;
    reg                    mag_busy;
    reg                    mag_we;
    reg                    mag_done_reg;
    reg                    mag_done_pending;
    reg [1:0]              mag_mode_latched;
    reg                    start_d;
    reg                    issuing_reads;
    reg                    read_valid_d;
    reg [2*CELL_WIDTH-1:0] read_addr_d;

    wire                   mag_start = start & ~start_d;

    reg                    stage1_valid;
    reg [2*CELL_WIDTH-1:0] stage1_addr;
    reg signed [DATA_WIDTH-1:0] stage1_ex, stage1_ey, stage1_bz;

    reg                    stage2_valid;
    reg [2*CELL_WIDTH-1:0] stage2_addr;
    reg [DATA_WIDTH-1:0]   stage2_e_mag;
    reg [DATA_WIDTH-1:0]   stage2_bz_abs;
    reg signed [DATA_WIDTH-1:0] stage2_ey_raw;

    reg                    stage3_valid;
    reg [2*CELL_WIDTH-1:0] stage3_addr;
    reg [DATA_WIDTH-1:0]   stage3_result;

    assign busy = mag_busy;
    assign done = mag_done_reg;
    assign mag_active  = mag_busy;            // borrow read port 0 the whole scan
    assign mag_addr    = mag_rd_addr;

    assign s_mag_addra = mag_wr_addr;
    assign s_mag_ena   = mag_busy | mag_we;
    assign s_mag_wea   = mag_we;
    assign s_mag_dina  = mag_wr_data;

    function [DATA_WIDTH-1:0] abs_unsigned;
        input signed [DATA_WIDTH-1:0] value;
        begin
            abs_unsigned = value[DATA_WIDTH-1] ?
                ((~value) + {{(DATA_WIDTH-1){1'b0}}, 1'b1}) : value;
        end
    endfunction

    function [DATA_WIDTH-1:0] e_mag_from_fields;
        input signed [DATA_WIDTH-1:0] ex_value;
        input signed [DATA_WIDTH-1:0] ey_value;
        reg [DATA_WIDTH-1:0] ex_abs, ey_abs, hi, lo;
        reg [DATA_WIDTH:0]   sum;
        begin
            ex_abs = abs_unsigned(ex_value);
            ey_abs = abs_unsigned(ey_value);
            hi = (ex_abs >= ey_abs) ? ex_abs : ey_abs;
            lo = (ex_abs >= ey_abs) ? ey_abs : ex_abs;
            sum = {1'b0, hi} + {2'b00, lo[DATA_WIDTH-1:1]};
            e_mag_from_fields = sum[DATA_WIDTH] ? {DATA_WIDTH{1'b1}} : sum[DATA_WIDTH-1:0];
        end
    endfunction

    function [DATA_WIDTH-1:0] s_mag_from_e_bz;
        input [DATA_WIDTH-1:0] e_value;
        input [DATA_WIDTH-1:0] bz_abs;
        reg [(2*DATA_WIDTH)-1:0] product, scaled;
        begin
            product = e_value * bz_abs;
            scaled  = product >> MAG_PRODUCT_SHIFT;
            s_mag_from_e_bz = |scaled[(2*DATA_WIDTH)-1:DATA_WIDTH] ?
                {DATA_WIDTH{1'b1}} : scaled[DATA_WIDTH-1:0];
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            start_d <= 1'b0; mag_rd_addr <= 0; mag_wr_addr <= 0; mag_wr_data <= 0;
            mag_busy <= 1'b0; mag_we <= 1'b0; mag_done_reg <= 1'b0; mag_done_pending <= 1'b0;
            mag_mode_latched <= 2'b0; issuing_reads <= 1'b0; read_valid_d <= 1'b0; read_addr_d <= 0;
            stage1_valid <= 1'b0; stage1_addr <= 0; stage1_ex <= 0; stage1_ey <= 0; stage1_bz <= 0;
            stage2_valid <= 1'b0; stage2_addr <= 0; stage2_e_mag <= 0; stage2_bz_abs <= 0; stage2_ey_raw <= 0;
            stage3_valid <= 1'b0; stage3_addr <= 0; stage3_result <= 0;
        end else begin
            start_d <= start;
            mag_we <= 1'b0;
            mag_done_reg <= mag_done_pending;
            mag_done_pending <= 1'b0;

            if (mag_start && !mag_busy) begin
                mag_rd_addr <= 0; mag_busy <= 1'b1; mag_mode_latched <= mag_mode;
                issuing_reads <= 1'b1; read_valid_d <= 1'b0; read_addr_d <= 0;
                stage1_valid <= 1'b0; stage2_valid <= 1'b0; stage3_valid <= 1'b0;
            end else if (mag_busy) begin
                mag_we      <= stage3_valid;
                mag_wr_addr <= stage3_addr;
                mag_wr_data <= stage3_result;

                if (stage3_valid && stage3_addr == LAST_ADDR) begin
                    mag_busy <= 1'b0; issuing_reads <= 1'b0; read_valid_d <= 1'b0;
                    stage1_valid <= 1'b0; stage2_valid <= 1'b0; stage3_valid <= 1'b0;
                    mag_done_pending <= 1'b1;
                end

                stage3_valid  <= stage2_valid;
                stage3_addr   <= stage2_addr;
                case (mag_mode_latched)
                    2'd1:    stage3_result <= s_mag_from_e_bz(stage2_e_mag, stage2_bz_abs);
                    2'd2:    stage3_result <= stage2_ey_raw;
                    default: stage3_result <= stage2_e_mag;
                endcase

                stage2_valid  <= stage1_valid;
                stage2_addr   <= stage1_addr;
                stage2_e_mag  <= e_mag_from_fields(stage1_ex, stage1_ey);
                stage2_bz_abs <= abs_unsigned(stage1_bz);
                stage2_ey_raw <= stage1_ey;

                stage1_valid <= read_valid_d;
                stage1_addr  <= read_addr_d;
                stage1_ex    <= mag_ex;
                stage1_ey    <= mag_ey;
                stage1_bz    <= mag_bz;

                if (issuing_reads) begin
                    read_valid_d <= 1'b1;
                    read_addr_d  <= mag_rd_addr;
                    if (mag_rd_addr == LAST_ADDR) issuing_reads <= 1'b0;
                    else mag_rd_addr <= mag_rd_addr + 1'b1;
                end else begin
                    read_valid_d <= 1'b0;
                end
            end
        end
    end
endmodule
