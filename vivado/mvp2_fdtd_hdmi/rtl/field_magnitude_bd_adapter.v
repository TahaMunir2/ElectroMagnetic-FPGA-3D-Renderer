`timescale 1ns/1ps

module field_magnitude_bd_adapter #(
    parameter CELLS = 64,
    parameter CELL_WIDTH = 6,
    parameter DATA_WIDTH = 16
)(
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire mag_mode,

    output wire busy,
    output wire done,

    input  wire [2*CELL_WIDTH-1:0] solver_ey_addra,
    input  wire                    solver_ey_ena,
    input  wire [0:0]              solver_ey_wea,
    input  wire [DATA_WIDTH-1:0]   solver_ey_dina,
    input  wire [2*CELL_WIDTH-1:0] solver_ey_addrb,
    input  wire                    solver_ey_enb,
    input  wire [0:0]              solver_ey_web,
    input  wire [DATA_WIDTH-1:0]   solver_ey_dinb,

    input  wire [2*CELL_WIDTH-1:0] solver_ex_addra,
    input  wire                    solver_ex_ena,
    input  wire [0:0]              solver_ex_wea,
    input  wire [DATA_WIDTH-1:0]   solver_ex_dina,
    input  wire [2*CELL_WIDTH-1:0] solver_ex_addrb,
    input  wire                    solver_ex_enb,
    input  wire [0:0]              solver_ex_web,
    input  wire [DATA_WIDTH-1:0]   solver_ex_dinb,

    input  wire [2*CELL_WIDTH-1:0] solver_bz_addra,
    input  wire                    solver_bz_ena,
    input  wire [0:0]              solver_bz_wea,
    input  wire [DATA_WIDTH-1:0]   solver_bz_dina,
    input  wire [2*CELL_WIDTH-1:0] solver_bz_addrb,
    input  wire                    solver_bz_enb,
    input  wire [0:0]              solver_bz_web,
    input  wire [DATA_WIDTH-1:0]   solver_bz_dinb,

    output wire [2*CELL_WIDTH-1:0] ey_addra,
    output wire                    ey_ena,
    output wire [0:0]              ey_wea,
    output wire [DATA_WIDTH-1:0]   ey_dina,
    input  wire [DATA_WIDTH-1:0]   ey_douta,
    output wire [2*CELL_WIDTH-1:0] ey_addrb,
    output wire                    ey_enb,
    output wire [0:0]              ey_web,
    output wire [DATA_WIDTH-1:0]   ey_dinb,

    output wire [2*CELL_WIDTH-1:0] ex_addra,
    output wire                    ex_ena,
    output wire [0:0]              ex_wea,
    output wire [DATA_WIDTH-1:0]   ex_dina,
    input  wire [DATA_WIDTH-1:0]   ex_douta,
    output wire [2*CELL_WIDTH-1:0] ex_addrb,
    output wire                    ex_enb,
    output wire [0:0]              ex_web,
    output wire [DATA_WIDTH-1:0]   ex_dinb,

    output wire [2*CELL_WIDTH-1:0] bz_addra,
    output wire                    bz_ena,
    output wire [0:0]              bz_wea,
    output wire [DATA_WIDTH-1:0]   bz_dina,
    input  wire [DATA_WIDTH-1:0]   bz_douta,
    output wire [2*CELL_WIDTH-1:0] bz_addrb,
    output wire                    bz_enb,
    output wire [0:0]              bz_web,
    output wire [DATA_WIDTH-1:0]   bz_dinb,

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
    reg                    mag_active;
    reg                    mag_we;
    reg                    mag_done_reg;
    reg                    mag_done_pending;
    reg                    mag_mode_latched;
    reg                    start_d;
    reg                    issuing_reads;
    reg                    read_valid_d;
    reg [2*CELL_WIDTH-1:0] read_addr_d;

    wire                   mag_start;

    reg                    stage1_valid;
    reg [2*CELL_WIDTH-1:0] stage1_addr;
    reg signed [DATA_WIDTH-1:0] stage1_ex;
    reg signed [DATA_WIDTH-1:0] stage1_ey;
    reg signed [DATA_WIDTH-1:0] stage1_bz;

    reg                    stage2_valid;
    reg [2*CELL_WIDTH-1:0] stage2_addr;
    reg [DATA_WIDTH-1:0]   stage2_e_mag;
    reg [DATA_WIDTH-1:0]   stage2_bz_abs;

    reg                    stage3_valid;
    reg [2*CELL_WIDTH-1:0] stage3_addr;
    reg [DATA_WIDTH-1:0]   stage3_result;

    assign mag_start = start & ~start_d;
    assign busy = mag_active;
    assign done = mag_done_reg;

    function [DATA_WIDTH-1:0] abs_unsigned;
        input signed [DATA_WIDTH-1:0] value;
        begin
            if (value[DATA_WIDTH-1])
                abs_unsigned = (~value) + {{(DATA_WIDTH-1){1'b0}}, 1'b1};
            else
                abs_unsigned = value;
        end
    endfunction

    function [DATA_WIDTH-1:0] e_mag_from_fields;
        input signed [DATA_WIDTH-1:0] ex_value;
        input signed [DATA_WIDTH-1:0] ey_value;
        reg [DATA_WIDTH-1:0] ex_abs;
        reg [DATA_WIDTH-1:0] ey_abs;
        reg [DATA_WIDTH-1:0] hi;
        reg [DATA_WIDTH-1:0] lo;
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

    function [DATA_WIDTH-1:0] s_mag_from_fields;
        input signed [DATA_WIDTH-1:0] ex_value;
        input signed [DATA_WIDTH-1:0] ey_value;
        input signed [DATA_WIDTH-1:0] bz_value;
        reg [DATA_WIDTH-1:0] e_approx;
        reg [DATA_WIDTH-1:0] bz_abs;
        reg [(2*DATA_WIDTH)-1:0] product;
        reg [(2*DATA_WIDTH)-1:0] scaled;
        begin
            e_approx = e_mag_from_fields(ex_value, ey_value);
            bz_abs = abs_unsigned(bz_value);
            product = e_approx * bz_abs;
            scaled = product >> MAG_PRODUCT_SHIFT;
            s_mag_from_fields = |scaled[(2*DATA_WIDTH)-1:DATA_WIDTH] ?
                {DATA_WIDTH{1'b1}} : scaled[DATA_WIDTH-1:0];
        end
    endfunction

    function [DATA_WIDTH-1:0] s_mag_from_e_bz;
        input [DATA_WIDTH-1:0] e_value;
        input [DATA_WIDTH-1:0] bz_abs;
        reg [(2*DATA_WIDTH)-1:0] product;
        reg [(2*DATA_WIDTH)-1:0] scaled;
        begin
            product = e_value * bz_abs;
            scaled = product >> MAG_PRODUCT_SHIFT;
            s_mag_from_e_bz = |scaled[(2*DATA_WIDTH)-1:DATA_WIDTH] ?
                {DATA_WIDTH{1'b1}} : scaled[DATA_WIDTH-1:0];
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            start_d          <= 1'b0;
            mag_rd_addr      <= {2*CELL_WIDTH{1'b0}};
            mag_wr_addr      <= {2*CELL_WIDTH{1'b0}};
            mag_wr_data      <= {DATA_WIDTH{1'b0}};
            mag_active       <= 1'b0;
            mag_we           <= 1'b0;
            mag_done_reg     <= 1'b0;
            mag_done_pending <= 1'b0;
            mag_mode_latched <= 1'b0;
            issuing_reads    <= 1'b0;
            read_valid_d     <= 1'b0;
            read_addr_d      <= {2*CELL_WIDTH{1'b0}};
            stage1_valid     <= 1'b0;
            stage1_addr      <= {2*CELL_WIDTH{1'b0}};
            stage1_ex        <= {DATA_WIDTH{1'b0}};
            stage1_ey        <= {DATA_WIDTH{1'b0}};
            stage1_bz        <= {DATA_WIDTH{1'b0}};
            stage2_valid     <= 1'b0;
            stage2_addr      <= {2*CELL_WIDTH{1'b0}};
            stage2_e_mag     <= {DATA_WIDTH{1'b0}};
            stage2_bz_abs    <= {DATA_WIDTH{1'b0}};
            stage3_valid     <= 1'b0;
            stage3_addr      <= {2*CELL_WIDTH{1'b0}};
            stage3_result    <= {DATA_WIDTH{1'b0}};
        end else begin
            start_d          <= start;
            mag_we           <= 1'b0;
            mag_done_reg     <= mag_done_pending;
            mag_done_pending <= 1'b0;

            if (mag_start && !mag_active) begin
                mag_rd_addr      <= {2*CELL_WIDTH{1'b0}};
                mag_active       <= 1'b1;
                mag_mode_latched <= mag_mode;
                issuing_reads    <= 1'b1;
                read_valid_d     <= 1'b0;
                read_addr_d      <= {2*CELL_WIDTH{1'b0}};
                stage1_valid     <= 1'b0;
                stage2_valid     <= 1'b0;
                stage3_valid     <= 1'b0;
            end else if (mag_active) begin
                mag_we      <= stage3_valid;
                mag_wr_addr <= stage3_addr;
                mag_wr_data <= stage3_result;

                if (stage3_valid && stage3_addr == LAST_ADDR) begin
                    mag_active       <= 1'b0;
                    issuing_reads    <= 1'b0;
                    read_valid_d     <= 1'b0;
                    stage1_valid     <= 1'b0;
                    stage2_valid     <= 1'b0;
                    stage3_valid     <= 1'b0;
                    mag_done_pending <= 1'b1;
                end

                stage3_valid  <= stage2_valid;
                stage3_addr   <= stage2_addr;
                stage3_result <= mag_mode_latched ?
                    s_mag_from_e_bz(stage2_e_mag, stage2_bz_abs) :
                    stage2_e_mag;

                stage2_valid  <= stage1_valid;
                stage2_addr   <= stage1_addr;
                stage2_e_mag  <= e_mag_from_fields(stage1_ex, stage1_ey);
                stage2_bz_abs <= abs_unsigned(stage1_bz);

                stage1_valid <= read_valid_d;
                stage1_addr  <= read_addr_d;
                stage1_ex    <= ex_douta;
                stage1_ey    <= ey_douta;
                stage1_bz    <= bz_douta;

                if (issuing_reads) begin
                    read_valid_d <= 1'b1;
                    read_addr_d  <= mag_rd_addr;
                    if (mag_rd_addr == LAST_ADDR) begin
                        issuing_reads <= 1'b0;
                    end else begin
                        mag_rd_addr <= mag_rd_addr + {{(2*CELL_WIDTH-1){1'b0}}, 1'b1};
                    end
                end else begin
                    read_valid_d <= 1'b0;
                end
            end
        end
    end

    assign ey_addra = mag_active ? mag_rd_addr : solver_ey_addra;
    assign ey_ena   = mag_active ? issuing_reads : solver_ey_ena;
    assign ey_wea   = mag_active ? 1'b0 : solver_ey_wea;
    assign ey_dina  = mag_active ? {DATA_WIDTH{1'b0}} : solver_ey_dina;
    assign ey_addrb = mag_active ? {2*CELL_WIDTH{1'b0}} : solver_ey_addrb;
    assign ey_enb   = mag_active ? 1'b0 : solver_ey_enb;
    assign ey_web   = mag_active ? 1'b0 : solver_ey_web;
    assign ey_dinb  = mag_active ? {DATA_WIDTH{1'b0}} : solver_ey_dinb;

    assign ex_addra = mag_active ? mag_rd_addr : solver_ex_addra;
    assign ex_ena   = mag_active ? issuing_reads : solver_ex_ena;
    assign ex_wea   = mag_active ? 1'b0 : solver_ex_wea;
    assign ex_dina  = mag_active ? {DATA_WIDTH{1'b0}} : solver_ex_dina;
    assign ex_addrb = mag_active ? {2*CELL_WIDTH{1'b0}} : solver_ex_addrb;
    assign ex_enb   = mag_active ? 1'b0 : solver_ex_enb;
    assign ex_web   = mag_active ? 1'b0 : solver_ex_web;
    assign ex_dinb  = mag_active ? {DATA_WIDTH{1'b0}} : solver_ex_dinb;

    assign bz_addra = mag_active ? mag_rd_addr : solver_bz_addra;
    assign bz_ena   = mag_active ? issuing_reads : solver_bz_ena;
    assign bz_wea   = mag_active ? 1'b0 : solver_bz_wea;
    assign bz_dina  = mag_active ? {DATA_WIDTH{1'b0}} : solver_bz_dina;
    assign bz_addrb = mag_active ? {2*CELL_WIDTH{1'b0}} : solver_bz_addrb;
    assign bz_enb   = mag_active ? 1'b0 : solver_bz_enb;
    assign bz_web   = mag_active ? 1'b0 : solver_bz_web;
    assign bz_dinb  = mag_active ? {DATA_WIDTH{1'b0}} : solver_bz_dinb;

    assign s_mag_addra = mag_wr_addr;
    assign s_mag_ena   = mag_active | mag_we;
    assign s_mag_wea   = mag_we;
    assign s_mag_dina  = mag_wr_data;

endmodule
