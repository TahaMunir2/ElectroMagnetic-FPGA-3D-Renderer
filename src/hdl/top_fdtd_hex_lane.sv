`timescale 1ns/1ps

module top_fdtd_hex_lane #(
    parameter LANES = 16,
    parameter TOTAL_ROWS = 128,
    parameter ROWS = TOTAL_ROWS / LANES,
    parameter COLUMNS = 128,
    parameter CELL_WIDTH = 7,
    parameter DATA_WIDTH = 16,
    parameter PML_SIZE = 6
)(
    input  wire clk,
    input  wire rst,
    input  wire [DATA_WIDTH-1:0] source_in,
    input  wire source_valid,
    input  wire [2*CELL_WIDTH-1:0] source_addr,
    input  wire solver_enable,
    output logic solver_done
);

    localparam GRID_SIZE = ROWS * COLUMNS;
    localparam ADDR_WIDTH = 2 * CELL_WIDTH;

    logic [3:0] source_lane;
    logic [ADDR_WIDTH-1:0] local_source_addr;

    assign source_lane = source_addr / GRID_SIZE;
    assign local_source_addr = source_addr - (source_lane * GRID_SIZE);

    logic [ADDR_WIDTH-1:0] ey_rd_addr_0 [15:0];
    logic [ADDR_WIDTH-1:0] ey_rd_addr_1 [15:0];
    logic [DATA_WIDTH-1:0] ey_rd_data_0 [15:0];
    logic [DATA_WIDTH-1:0] ey_rd_data_1 [15:0];
    logic ey_we [15:0];
    logic [ADDR_WIDTH-1:0] ey_wr_addr [15:0];
    logic [DATA_WIDTH-1:0] ey_wr_data [15:0];

    logic [ADDR_WIDTH-1:0] ex_rd_addr_0 [15:0];
    logic [DATA_WIDTH-1:0] ex_rd_data_0 [15:0];
    logic ex_we [15:0];
    logic [ADDR_WIDTH-1:0] ex_wr_addr [15:0];
    logic [DATA_WIDTH-1:0] ex_wr_data [15:0];

    logic [ADDR_WIDTH-1:0] bz_rd_addr_0 [15:0];
    logic [ADDR_WIDTH-1:0] bz_rd_addr_1 [15:0];
    logic [DATA_WIDTH-1:0] bz_rd_data_0 [15:0];
    logic [DATA_WIDTH-1:0] bz_rd_data_1 [15:0];
    logic bz_we [15:0];
    logic [ADDR_WIDTH-1:0] bz_wr_addr [15:0];
    logic [DATA_WIDTH-1:0] bz_wr_data [15:0];

    logic [ADDR_WIDTH-1:0] slv_ey_rd_addr [15:0];
    logic [ADDR_WIDTH-1:0] slv_ey_wr_addr [15:0];
    logic [DATA_WIDTH-1:0] slv_ey_wr_data [15:0];
    logic slv_ey_we [15:0];
    logic [ADDR_WIDTH-1:0] slv_ex_rd_addr [15:0];
    logic [ADDR_WIDTH-1:0] slv_ex_wr_addr [15:0];
    logic [DATA_WIDTH-1:0] slv_ex_wr_data [15:0];
    logic slv_ex_we [15:0];
    logic [ADDR_WIDTH-1:0] slv_bz_rd_addr [15:0];
    logic [ADDR_WIDTH-1:0] slv_bz_wr_addr [15:0];
    logic [DATA_WIDTH-1:0] slv_bz_wr_data [15:0];
    logic slv_bz_we [15:0];
    logic [ADDR_WIDTH-1:0] slv_bz_adj_rd_addr [15:0];
    logic [DATA_WIDTH-1:0] slv_bz_adj_dout [15:0];
    logic [ADDR_WIDTH-1:0] slv_ey_adj_rd_addr [15:0];
    logic [DATA_WIDTH-1:0] slv_ey_adj_dout [15:0];
    logic slv_done [15:0];
    logic [CELL_WIDTH-1:0] slv_current_row [15:0];
    logic [CELL_WIDTH-1:0] slv_current_col [15:0];
    logic slv_e_phase [15:0];

    logic [CELL_WIDTH-1:0] prev_row [15:0];
    logic prev_phase [15:0];

    always_ff @(posedge clk) begin
        prev_row[0]  <= slv_current_row[0];
        prev_phase[0] <= slv_e_phase[0];
        prev_row[1]  <= slv_current_row[1];
        prev_phase[1] <= slv_e_phase[1];
        prev_row[2]  <= slv_current_row[2];
        prev_phase[2] <= slv_e_phase[2];
        prev_row[3]  <= slv_current_row[3];
        prev_phase[3] <= slv_e_phase[3];
        prev_row[4]  <= slv_current_row[4];
        prev_phase[4] <= slv_e_phase[4];
        prev_row[5]  <= slv_current_row[5];
        prev_phase[5] <= slv_e_phase[5];
        prev_row[6]  <= slv_current_row[6];
        prev_phase[6] <= slv_e_phase[6];
        prev_row[7]  <= slv_current_row[7];
        prev_phase[7] <= slv_e_phase[7];
        prev_row[8]  <= slv_current_row[8];
        prev_phase[8] <= slv_e_phase[8];
        prev_row[9]  <= slv_current_row[9];
        prev_phase[9] <= slv_e_phase[9];
        prev_row[10] <= slv_current_row[10];
        prev_phase[10] <= slv_e_phase[10];
        prev_row[11] <= slv_current_row[11];
        prev_phase[11] <= slv_e_phase[11];
        prev_row[12] <= slv_current_row[12];
        prev_phase[12] <= slv_e_phase[12];
        prev_row[13] <= slv_current_row[13];
        prev_phase[13] <= slv_e_phase[13];
        prev_row[14] <= slv_current_row[14];
        prev_phase[14] <= slv_e_phase[14];
        prev_row[15] <= slv_current_row[15];
        prev_phase[15] <= slv_e_phase[15];
    end

    assign ey_rd_addr_0 = slv_ey_rd_addr;
    assign ex_rd_addr_0 = slv_ex_rd_addr;
    assign bz_rd_addr_0 = slv_bz_rd_addr;
    assign ey_we = slv_ey_we;
    assign ey_wr_addr = slv_ey_wr_addr;
    assign ey_wr_data = slv_ey_wr_data;
    assign ex_we = slv_ex_we;
    assign ex_wr_addr = slv_ex_wr_addr;
    assign ex_wr_data = slv_ex_wr_data;
    assign bz_we = slv_bz_we;
    assign bz_wr_addr = slv_bz_wr_addr;
    assign bz_wr_data = slv_bz_wr_data;

    always_comb begin
        bz_rd_addr_1[0]  = slv_bz_adj_rd_addr[0];
        bz_rd_addr_1[1]  = slv_bz_adj_rd_addr[1];
        bz_rd_addr_1[2]  = slv_bz_adj_rd_addr[2];
        bz_rd_addr_1[3]  = slv_bz_adj_rd_addr[3];
        bz_rd_addr_1[4]  = slv_bz_adj_rd_addr[4];
        bz_rd_addr_1[5]  = slv_bz_adj_rd_addr[5];
        bz_rd_addr_1[6]  = slv_bz_adj_rd_addr[6];
        bz_rd_addr_1[7]  = slv_bz_adj_rd_addr[7];
        bz_rd_addr_1[8]  = slv_bz_adj_rd_addr[8];
        bz_rd_addr_1[9]  = slv_bz_adj_rd_addr[9];
        bz_rd_addr_1[10] = slv_bz_adj_rd_addr[10];
        bz_rd_addr_1[11] = slv_bz_adj_rd_addr[11];
        bz_rd_addr_1[12] = slv_bz_adj_rd_addr[12];
        bz_rd_addr_1[13] = slv_bz_adj_rd_addr[13];
        bz_rd_addr_1[14] = slv_bz_adj_rd_addr[14];
        bz_rd_addr_1[15] = slv_bz_adj_rd_addr[15];
        ey_rd_addr_1[0]  = slv_ey_adj_rd_addr[0];
        ey_rd_addr_1[1]  = slv_ey_adj_rd_addr[1];
        ey_rd_addr_1[2]  = slv_ey_adj_rd_addr[2];
        ey_rd_addr_1[3]  = slv_ey_adj_rd_addr[3];
        ey_rd_addr_1[4]  = slv_ey_adj_rd_addr[4];
        ey_rd_addr_1[5]  = slv_ey_adj_rd_addr[5];
        ey_rd_addr_1[6]  = slv_ey_adj_rd_addr[6];
        ey_rd_addr_1[7]  = slv_ey_adj_rd_addr[7];
        ey_rd_addr_1[8]  = slv_ey_adj_rd_addr[8];
        ey_rd_addr_1[9]  = slv_ey_adj_rd_addr[9];
        ey_rd_addr_1[10] = slv_ey_adj_rd_addr[10];
        ey_rd_addr_1[11] = slv_ey_adj_rd_addr[11];
        ey_rd_addr_1[12] = slv_ey_adj_rd_addr[12];
        ey_rd_addr_1[13] = slv_ey_adj_rd_addr[13];
        ey_rd_addr_1[14] = slv_ey_adj_rd_addr[14];
        ey_rd_addr_1[15] = slv_ey_adj_rd_addr[15];

        if (!slv_e_phase[1] && slv_current_row[1] == 0)
            bz_rd_addr_1[0] = (ROWS-1)*COLUMNS + slv_current_col[1];
        if (slv_e_phase[0] && slv_current_row[0] == ROWS-1)
            ey_rd_addr_1[1] = slv_current_col[0];

        if (!slv_e_phase[2] && slv_current_row[2] == 0)
            bz_rd_addr_1[1] = (ROWS-1)*COLUMNS + slv_current_col[2];
        if (slv_e_phase[1] && slv_current_row[1] == ROWS-1)
            ey_rd_addr_1[2] = slv_current_col[1];

        if (!slv_e_phase[3] && slv_current_row[3] == 0)
            bz_rd_addr_1[2] = (ROWS-1)*COLUMNS + slv_current_col[3];
        if (slv_e_phase[2] && slv_current_row[2] == ROWS-1)
            ey_rd_addr_1[3] = slv_current_col[2];

        if (!slv_e_phase[4] && slv_current_row[4] == 0)
            bz_rd_addr_1[3] = (ROWS-1)*COLUMNS + slv_current_col[4];
        if (slv_e_phase[3] && slv_current_row[3] == ROWS-1)
            ey_rd_addr_1[4] = slv_current_col[3];

        if (!slv_e_phase[5] && slv_current_row[5] == 0)
            bz_rd_addr_1[4] = (ROWS-1)*COLUMNS + slv_current_col[5];
        if (slv_e_phase[4] && slv_current_row[4] == ROWS-1)
            ey_rd_addr_1[5] = slv_current_col[4];

        if (!slv_e_phase[6] && slv_current_row[6] == 0)
            bz_rd_addr_1[5] = (ROWS-1)*COLUMNS + slv_current_col[6];
        if (slv_e_phase[5] && slv_current_row[5] == ROWS-1)
            ey_rd_addr_1[6] = slv_current_col[5];

        if (!slv_e_phase[7] && slv_current_row[7] == 0)
            bz_rd_addr_1[6] = (ROWS-1)*COLUMNS + slv_current_col[7];
        if (slv_e_phase[6] && slv_current_row[6] == ROWS-1)
            ey_rd_addr_1[7] = slv_current_col[6];

        if (!slv_e_phase[8] && slv_current_row[8] == 0)
            bz_rd_addr_1[7] = (ROWS-1)*COLUMNS + slv_current_col[8];
        if (slv_e_phase[7] && slv_current_row[7] == ROWS-1)
            ey_rd_addr_1[8] = slv_current_col[7];

        if (!slv_e_phase[9] && slv_current_row[9] == 0)
            bz_rd_addr_1[8] = (ROWS-1)*COLUMNS + slv_current_col[9];
        if (slv_e_phase[8] && slv_current_row[8] == ROWS-1)
            ey_rd_addr_1[9] = slv_current_col[8];

        if (!slv_e_phase[10] && slv_current_row[10] == 0)
            bz_rd_addr_1[9] = (ROWS-1)*COLUMNS + slv_current_col[10];
        if (slv_e_phase[9] && slv_current_row[9] == ROWS-1)
            ey_rd_addr_1[10] = slv_current_col[9];

        if (!slv_e_phase[11] && slv_current_row[11] == 0)
            bz_rd_addr_1[10] = (ROWS-1)*COLUMNS + slv_current_col[11];
        if (slv_e_phase[10] && slv_current_row[10] == ROWS-1)
            ey_rd_addr_1[11] = slv_current_col[10];

        if (!slv_e_phase[12] && slv_current_row[12] == 0)
            bz_rd_addr_1[11] = (ROWS-1)*COLUMNS + slv_current_col[12];
        if (slv_e_phase[11] && slv_current_row[11] == ROWS-1)
            ey_rd_addr_1[12] = slv_current_col[11];

        if (!slv_e_phase[13] && slv_current_row[13] == 0)
            bz_rd_addr_1[12] = (ROWS-1)*COLUMNS + slv_current_col[13];
        if (slv_e_phase[12] && slv_current_row[12] == ROWS-1)
            ey_rd_addr_1[13] = slv_current_col[12];

        if (!slv_e_phase[14] && slv_current_row[14] == 0)
            bz_rd_addr_1[13] = (ROWS-1)*COLUMNS + slv_current_col[14];
        if (slv_e_phase[13] && slv_current_row[13] == ROWS-1)
            ey_rd_addr_1[14] = slv_current_col[13];

        if (!slv_e_phase[15] && slv_current_row[15] == 0)
            bz_rd_addr_1[14] = (ROWS-1)*COLUMNS + slv_current_col[15];
        if (slv_e_phase[14] && slv_current_row[14] == ROWS-1)
            ey_rd_addr_1[15] = slv_current_col[14];
    end

    always_comb begin
        slv_bz_adj_dout[0]  = bz_rd_data_1[0];
        slv_bz_adj_dout[1]  = bz_rd_data_1[1];
        slv_bz_adj_dout[2]  = bz_rd_data_1[2];
        slv_bz_adj_dout[3]  = bz_rd_data_1[3];
        slv_bz_adj_dout[4]  = bz_rd_data_1[4];
        slv_bz_adj_dout[5]  = bz_rd_data_1[5];
        slv_bz_adj_dout[6]  = bz_rd_data_1[6];
        slv_bz_adj_dout[7]  = bz_rd_data_1[7];
        slv_bz_adj_dout[8]  = bz_rd_data_1[8];
        slv_bz_adj_dout[9]  = bz_rd_data_1[9];
        slv_bz_adj_dout[10] = bz_rd_data_1[10];
        slv_bz_adj_dout[11] = bz_rd_data_1[11];
        slv_bz_adj_dout[12] = bz_rd_data_1[12];
        slv_bz_adj_dout[13] = bz_rd_data_1[13];
        slv_bz_adj_dout[14] = bz_rd_data_1[14];
        slv_bz_adj_dout[15] = bz_rd_data_1[15];
        slv_ey_adj_dout[0]  = ey_rd_data_1[0];
        slv_ey_adj_dout[1]  = ey_rd_data_1[1];
        slv_ey_adj_dout[2]  = ey_rd_data_1[2];
        slv_ey_adj_dout[3]  = ey_rd_data_1[3];
        slv_ey_adj_dout[4]  = ey_rd_data_1[4];
        slv_ey_adj_dout[5]  = ey_rd_data_1[5];
        slv_ey_adj_dout[6]  = ey_rd_data_1[6];
        slv_ey_adj_dout[7]  = ey_rd_data_1[7];
        slv_ey_adj_dout[8]  = ey_rd_data_1[8];
        slv_ey_adj_dout[9]  = ey_rd_data_1[9];
        slv_ey_adj_dout[10] = ey_rd_data_1[10];
        slv_ey_adj_dout[11] = ey_rd_data_1[11];
        slv_ey_adj_dout[12] = ey_rd_data_1[12];
        slv_ey_adj_dout[13] = ey_rd_data_1[13];
        slv_ey_adj_dout[14] = ey_rd_data_1[14];
        slv_ey_adj_dout[15] = ey_rd_data_1[15];

        if (!prev_phase[1] && prev_row[1] == 0)
            slv_bz_adj_dout[1] = bz_rd_data_1[0];
        if (prev_phase[0] && prev_row[0] == ROWS-1)
            slv_ey_adj_dout[0] = ey_rd_data_1[1];

        if (!prev_phase[2] && prev_row[2] == 0)
            slv_bz_adj_dout[2] = bz_rd_data_1[1];
        if (prev_phase[1] && prev_row[1] == ROWS-1)
            slv_ey_adj_dout[1] = ey_rd_data_1[2];

        if (!prev_phase[3] && prev_row[3] == 0)
            slv_bz_adj_dout[3] = bz_rd_data_1[2];
        if (prev_phase[2] && prev_row[2] == ROWS-1)
            slv_ey_adj_dout[2] = ey_rd_data_1[3];

        if (!prev_phase[4] && prev_row[4] == 0)
            slv_bz_adj_dout[4] = bz_rd_data_1[3];
        if (prev_phase[3] && prev_row[3] == ROWS-1)
            slv_ey_adj_dout[3] = ey_rd_data_1[4];

        if (!prev_phase[5] && prev_row[5] == 0)
            slv_bz_adj_dout[5] = bz_rd_data_1[4];
        if (prev_phase[4] && prev_row[4] == ROWS-1)
            slv_ey_adj_dout[4] = ey_rd_data_1[5];

        if (!prev_phase[6] && prev_row[6] == 0)
            slv_bz_adj_dout[6] = bz_rd_data_1[5];
        if (prev_phase[5] && prev_row[5] == ROWS-1)
            slv_ey_adj_dout[5] = ey_rd_data_1[6];

        if (!prev_phase[7] && prev_row[7] == 0)
            slv_bz_adj_dout[7] = bz_rd_data_1[6];
        if (prev_phase[6] && prev_row[6] == ROWS-1)
            slv_ey_adj_dout[6] = ey_rd_data_1[7];

        if (!prev_phase[8] && prev_row[8] == 0)
            slv_bz_adj_dout[8] = bz_rd_data_1[7];
        if (prev_phase[7] && prev_row[7] == ROWS-1)
            slv_ey_adj_dout[7] = ey_rd_data_1[8];

        if (!prev_phase[9] && prev_row[9] == 0)
            slv_bz_adj_dout[9] = bz_rd_data_1[8];
        if (prev_phase[8] && prev_row[8] == ROWS-1)
            slv_ey_adj_dout[8] = ey_rd_data_1[9];

        if (!prev_phase[10] && prev_row[10] == 0)
            slv_bz_adj_dout[10] = bz_rd_data_1[9];
        if (prev_phase[9] && prev_row[9] == ROWS-1)
            slv_ey_adj_dout[9] = ey_rd_data_1[10];

        if (!prev_phase[11] && prev_row[11] == 0)
            slv_bz_adj_dout[11] = bz_rd_data_1[10];
        if (prev_phase[10] && prev_row[10] == ROWS-1)
            slv_ey_adj_dout[10] = ey_rd_data_1[11];

        if (!prev_phase[12] && prev_row[12] == 0)
            slv_bz_adj_dout[12] = bz_rd_data_1[11];
        if (prev_phase[11] && prev_row[11] == ROWS-1)
            slv_ey_adj_dout[11] = ey_rd_data_1[12];

        if (!prev_phase[13] && prev_row[13] == 0)
            slv_bz_adj_dout[13] = bz_rd_data_1[12];
        if (prev_phase[12] && prev_row[12] == ROWS-1)
            slv_ey_adj_dout[12] = ey_rd_data_1[13];

        if (!prev_phase[14] && prev_row[14] == 0)
            slv_bz_adj_dout[14] = bz_rd_data_1[13];
        if (prev_phase[13] && prev_row[13] == ROWS-1)
            slv_ey_adj_dout[13] = ey_rd_data_1[14];

        if (!prev_phase[15] && prev_row[15] == 0)
            slv_bz_adj_dout[15] = bz_rd_data_1[14];
        if (prev_phase[14] && prev_row[14] == ROWS-1)
            slv_ey_adj_dout[14] = ey_rd_data_1[15];
    end

    assign solver_done = slv_done[0]  & slv_done[1]  & slv_done[2]  & slv_done[3]  &
                         slv_done[4]  & slv_done[5]  & slv_done[6]  & slv_done[7]  &
                         slv_done[8]  & slv_done[9]  & slv_done[10] & slv_done[11] &
                         slv_done[12] & slv_done[13] & slv_done[14] & slv_done[15];

    bram_module #(
        .DEPTH(GRID_SIZE),
        .WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) bram_0 (
        .clk(clk),
        .rst(rst),
        .ey_rd_addr_0(ey_rd_addr_0[0]),
        .ey_rd_data_0(ey_rd_data_0[0]),
        .ey_rd_addr_1(ey_rd_addr_1[0]),
        .ey_rd_data_1(ey_rd_data_1[0]),
        .ex_rd_addr_0(ex_rd_addr_0[0]),
        .ex_rd_data_0(ex_rd_data_0[0]),
        .ex_rd_addr_1('0),
        .ex_rd_data_1(),
        .bz_rd_addr_0(bz_rd_addr_0[0]),
        .bz_rd_data_0(bz_rd_data_0[0]),
        .bz_rd_addr_1(bz_rd_addr_1[0]),
        .bz_rd_data_1(bz_rd_data_1[0]),
        .ey_we(ey_we[0]),
        .ey_wr_addr(ey_wr_addr[0]),
        .ey_wr_data(ey_wr_data[0]),
        .ex_we(ex_we[0]),
        .ex_wr_addr(ex_wr_addr[0]),
        .ex_wr_data(ex_wr_data[0]),
        .bz_we(bz_we[0]),
        .bz_wr_addr(bz_wr_addr[0]),
        .bz_wr_data(bz_wr_data[0])
    );

    bram_module #(
        .DEPTH(GRID_SIZE),
        .WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) bram_1 (
        .clk(clk),
        .rst(rst),
        .ey_rd_addr_0(ey_rd_addr_0[1]),
        .ey_rd_data_0(ey_rd_data_0[1]),
        .ey_rd_addr_1(ey_rd_addr_1[1]),
        .ey_rd_data_1(ey_rd_data_1[1]),
        .ex_rd_addr_0(ex_rd_addr_0[1]),
        .ex_rd_data_0(ex_rd_data_0[1]),
        .ex_rd_addr_1('0),
        .ex_rd_data_1(),
        .bz_rd_addr_0(bz_rd_addr_0[1]),
        .bz_rd_data_0(bz_rd_data_0[1]),
        .bz_rd_addr_1(bz_rd_addr_1[1]),
        .bz_rd_data_1(bz_rd_data_1[1]),
        .ey_we(ey_we[1]),
        .ey_wr_addr(ey_wr_addr[1]),
        .ey_wr_data(ey_wr_data[1]),
        .ex_we(ex_we[1]),
        .ex_wr_addr(ex_wr_addr[1]),
        .ex_wr_data(ex_wr_data[1]),
        .bz_we(bz_we[1]),
        .bz_wr_addr(bz_wr_addr[1]),
        .bz_wr_data(bz_wr_data[1])
    );

    bram_module #(
        .DEPTH(GRID_SIZE),
        .WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) bram_2 (
        .clk(clk),
        .rst(rst),
        .ey_rd_addr_0(ey_rd_addr_0[2]),
        .ey_rd_data_0(ey_rd_data_0[2]),
        .ey_rd_addr_1(ey_rd_addr_1[2]),
        .ey_rd_data_1(ey_rd_data_1[2]),
        .ex_rd_addr_0(ex_rd_addr_0[2]),
        .ex_rd_data_0(ex_rd_data_0[2]),
        .ex_rd_addr_1('0),
        .ex_rd_data_1(),
        .bz_rd_addr_0(bz_rd_addr_0[2]),
        .bz_rd_data_0(bz_rd_data_0[2]),
        .bz_rd_addr_1(bz_rd_addr_1[2]),
        .bz_rd_data_1(bz_rd_data_1[2]),
        .ey_we(ey_we[2]),
        .ey_wr_addr(ey_wr_addr[2]),
        .ey_wr_data(ey_wr_data[2]),
        .ex_we(ex_we[2]),
        .ex_wr_addr(ex_wr_addr[2]),
        .ex_wr_data(ex_wr_data[2]),
        .bz_we(bz_we[2]),
        .bz_wr_addr(bz_wr_addr[2]),
        .bz_wr_data(bz_wr_data[2])
    );

    bram_module #(
        .DEPTH(GRID_SIZE),
        .WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) bram_3 (
        .clk(clk),
        .rst(rst),
        .ey_rd_addr_0(ey_rd_addr_0[3]),
        .ey_rd_data_0(ey_rd_data_0[3]),
        .ey_rd_addr_1(ey_rd_addr_1[3]),
        .ey_rd_data_1(ey_rd_data_1[3]),
        .ex_rd_addr_0(ex_rd_addr_0[3]),
        .ex_rd_data_0(ex_rd_data_0[3]),
        .ex_rd_addr_1('0),
        .ex_rd_data_1(),
        .bz_rd_addr_0(bz_rd_addr_0[3]),
        .bz_rd_data_0(bz_rd_data_0[3]),
        .bz_rd_addr_1(bz_rd_addr_1[3]),
        .bz_rd_data_1(bz_rd_data_1[3]),
        .ey_we(ey_we[3]),
        .ey_wr_addr(ey_wr_addr[3]),
        .ey_wr_data(ey_wr_data[3]),
        .ex_we(ex_we[3]),
        .ex_wr_addr(ex_wr_addr[3]),
        .ex_wr_data(ex_wr_data[3]),
        .bz_we(bz_we[3]),
        .bz_wr_addr(bz_wr_addr[3]),
        .bz_wr_data(bz_wr_data[3])
    );

    bram_module #(
        .DEPTH(GRID_SIZE),
        .WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) bram_4 (
        .clk(clk),
        .rst(rst),
        .ey_rd_addr_0(ey_rd_addr_0[4]),
        .ey_rd_data_0(ey_rd_data_0[4]),
        .ey_rd_addr_1(ey_rd_addr_1[4]),
        .ey_rd_data_1(ey_rd_data_1[4]),
        .ex_rd_addr_0(ex_rd_addr_0[4]),
        .ex_rd_data_0(ex_rd_data_0[4]),
        .ex_rd_addr_1('0),
        .ex_rd_data_1(),
        .bz_rd_addr_0(bz_rd_addr_0[4]),
        .bz_rd_data_0(bz_rd_data_0[4]),
        .bz_rd_addr_1(bz_rd_addr_1[4]),
        .bz_rd_data_1(bz_rd_data_1[4]),
        .ey_we(ey_we[4]),
        .ey_wr_addr(ey_wr_addr[4]),
        .ey_wr_data(ey_wr_data[4]),
        .ex_we(ex_we[4]),
        .ex_wr_addr(ex_wr_addr[4]),
        .ex_wr_data(ex_wr_data[4]),
        .bz_we(bz_we[4]),
        .bz_wr_addr(bz_wr_addr[4]),
        .bz_wr_data(bz_wr_data[4])
    );

    bram_module #(
        .DEPTH(GRID_SIZE),
        .WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) bram_5 (
        .clk(clk),
        .rst(rst),
        .ey_rd_addr_0(ey_rd_addr_0[5]),
        .ey_rd_data_0(ey_rd_data_0[5]),
        .ey_rd_addr_1(ey_rd_addr_1[5]),
        .ey_rd_data_1(ey_rd_data_1[5]),
        .ex_rd_addr_0(ex_rd_addr_0[5]),
        .ex_rd_data_0(ex_rd_data_0[5]),
        .ex_rd_addr_1('0),
        .ex_rd_data_1(),
        .bz_rd_addr_0(bz_rd_addr_0[5]),
        .bz_rd_data_0(bz_rd_data_0[5]),
        .bz_rd_addr_1(bz_rd_addr_1[5]),
        .bz_rd_data_1(bz_rd_data_1[5]),
        .ey_we(ey_we[5]),
        .ey_wr_addr(ey_wr_addr[5]),
        .ey_wr_data(ey_wr_data[5]),
        .ex_we(ex_we[5]),
        .ex_wr_addr(ex_wr_addr[5]),
        .ex_wr_data(ex_wr_data[5]),
        .bz_we(bz_we[5]),
        .bz_wr_addr(bz_wr_addr[5]),
        .bz_wr_data(bz_wr_data[5])
    );

    bram_module #(
        .DEPTH(GRID_SIZE),
        .WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) bram_6 (
        .clk(clk),
        .rst(rst),
        .ey_rd_addr_0(ey_rd_addr_0[6]),
        .ey_rd_data_0(ey_rd_data_0[6]),
        .ey_rd_addr_1(ey_rd_addr_1[6]),
        .ey_rd_data_1(ey_rd_data_1[6]),
        .ex_rd_addr_0(ex_rd_addr_0[6]),
        .ex_rd_data_0(ex_rd_data_0[6]),
        .ex_rd_addr_1('0),
        .ex_rd_data_1(),
        .bz_rd_addr_0(bz_rd_addr_0[6]),
        .bz_rd_data_0(bz_rd_data_0[6]),
        .bz_rd_addr_1(bz_rd_addr_1[6]),
        .bz_rd_data_1(bz_rd_data_1[6]),
        .ey_we(ey_we[6]),
        .ey_wr_addr(ey_wr_addr[6]),
        .ey_wr_data(ey_wr_data[6]),
        .ex_we(ex_we[6]),
        .ex_wr_addr(ex_wr_addr[6]),
        .ex_wr_data(ex_wr_data[6]),
        .bz_we(bz_we[6]),
        .bz_wr_addr(bz_wr_addr[6]),
        .bz_wr_data(bz_wr_data[6])
    );

    bram_module #(
        .DEPTH(GRID_SIZE),
        .WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) bram_7 (
        .clk(clk),
        .rst(rst),
        .ey_rd_addr_0(ey_rd_addr_0[7]),
        .ey_rd_data_0(ey_rd_data_0[7]),
        .ey_rd_addr_1(ey_rd_addr_1[7]),
        .ey_rd_data_1(ey_rd_data_1[7]),
        .ex_rd_addr_0(ex_rd_addr_0[7]),
        .ex_rd_data_0(ex_rd_data_0[7]),
        .ex_rd_addr_1('0),
        .ex_rd_data_1(),
        .bz_rd_addr_0(bz_rd_addr_0[7]),
        .bz_rd_data_0(bz_rd_data_0[7]),
        .bz_rd_addr_1(bz_rd_addr_1[7]),
        .bz_rd_data_1(bz_rd_data_1[7]),
        .ey_we(ey_we[7]),
        .ey_wr_addr(ey_wr_addr[7]),
        .ey_wr_data(ey_wr_data[7]),
        .ex_we(ex_we[7]),
        .ex_wr_addr(ex_wr_addr[7]),
        .ex_wr_data(ex_wr_data[7]),
        .bz_we(bz_we[7]),
        .bz_wr_addr(bz_wr_addr[7]),
        .bz_wr_data(bz_wr_data[7])
    );

    bram_module #(
        .DEPTH(GRID_SIZE),
        .WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) bram_8 (
        .clk(clk),
        .rst(rst),
        .ey_rd_addr_0(ey_rd_addr_0[8]),
        .ey_rd_data_0(ey_rd_data_0[8]),
        .ey_rd_addr_1(ey_rd_addr_1[8]),
        .ey_rd_data_1(ey_rd_data_1[8]),
        .ex_rd_addr_0(ex_rd_addr_0[8]),
        .ex_rd_data_0(ex_rd_data_0[8]),
        .ex_rd_addr_1('0),
        .ex_rd_data_1(),
        .bz_rd_addr_0(bz_rd_addr_0[8]),
        .bz_rd_data_0(bz_rd_data_0[8]),
        .bz_rd_addr_1(bz_rd_addr_1[8]),
        .bz_rd_data_1(bz_rd_data_1[8]),
        .ey_we(ey_we[8]),
        .ey_wr_addr(ey_wr_addr[8]),
        .ey_wr_data(ey_wr_data[8]),
        .ex_we(ex_we[8]),
        .ex_wr_addr(ex_wr_addr[8]),
        .ex_wr_data(ex_wr_data[8]),
        .bz_we(bz_we[8]),
        .bz_wr_addr(bz_wr_addr[8]),
        .bz_wr_data(bz_wr_data[8])
    );

    bram_module #(
        .DEPTH(GRID_SIZE),
        .WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) bram_9 (
        .clk(clk),
        .rst(rst),
        .ey_rd_addr_0(ey_rd_addr_0[9]),
        .ey_rd_data_0(ey_rd_data_0[9]),
        .ey_rd_addr_1(ey_rd_addr_1[9]),
        .ey_rd_data_1(ey_rd_data_1[9]),
        .ex_rd_addr_0(ex_rd_addr_0[9]),
        .ex_rd_data_0(ex_rd_data_0[9]),
        .ex_rd_addr_1('0),
        .ex_rd_data_1(),
        .bz_rd_addr_0(bz_rd_addr_0[9]),
        .bz_rd_data_0(bz_rd_data_0[9]),
        .bz_rd_addr_1(bz_rd_addr_1[9]),
        .bz_rd_data_1(bz_rd_data_1[9]),
        .ey_we(ey_we[9]),
        .ey_wr_addr(ey_wr_addr[9]),
        .ey_wr_data(ey_wr_data[9]),
        .ex_we(ex_we[9]),
        .ex_wr_addr(ex_wr_addr[9]),
        .ex_wr_data(ex_wr_data[9]),
        .bz_we(bz_we[9]),
        .bz_wr_addr(bz_wr_addr[9]),
        .bz_wr_data(bz_wr_data[9])
    );

    bram_module #(
        .DEPTH(GRID_SIZE),
        .WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) bram_10 (
        .clk(clk),
        .rst(rst),
        .ey_rd_addr_0(ey_rd_addr_0[10]),
        .ey_rd_data_0(ey_rd_data_0[10]),
        .ey_rd_addr_1(ey_rd_addr_1[10]),
        .ey_rd_data_1(ey_rd_data_1[10]),
        .ex_rd_addr_0(ex_rd_addr_0[10]),
        .ex_rd_data_0(ex_rd_data_0[10]),
        .ex_rd_addr_1('0),
        .ex_rd_data_1(),
        .bz_rd_addr_0(bz_rd_addr_0[10]),
        .bz_rd_data_0(bz_rd_data_0[10]),
        .bz_rd_addr_1(bz_rd_addr_1[10]),
        .bz_rd_data_1(bz_rd_data_1[10]),
        .ey_we(ey_we[10]),
        .ey_wr_addr(ey_wr_addr[10]),
        .ey_wr_data(ey_wr_data[10]),
        .ex_we(ex_we[10]),
        .ex_wr_addr(ex_wr_addr[10]),
        .ex_wr_data(ex_wr_data[10]),
        .bz_we(bz_we[10]),
        .bz_wr_addr(bz_wr_addr[10]),
        .bz_wr_data(bz_wr_data[10])
    );

    bram_module #(
        .DEPTH(GRID_SIZE),
        .WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) bram_11 (
        .clk(clk),
        .rst(rst),
        .ey_rd_addr_0(ey_rd_addr_0[11]),
        .ey_rd_data_0(ey_rd_data_0[11]),
        .ey_rd_addr_1(ey_rd_addr_1[11]),
        .ey_rd_data_1(ey_rd_data_1[11]),
        .ex_rd_addr_0(ex_rd_addr_0[11]),
        .ex_rd_data_0(ex_rd_data_0[11]),
        .ex_rd_addr_1('0),
        .ex_rd_data_1(),
        .bz_rd_addr_0(bz_rd_addr_0[11]),
        .bz_rd_data_0(bz_rd_data_0[11]),
        .bz_rd_addr_1(bz_rd_addr_1[11]),
        .bz_rd_data_1(bz_rd_data_1[11]),
        .ey_we(ey_we[11]),
        .ey_wr_addr(ey_wr_addr[11]),
        .ey_wr_data(ey_wr_data[11]),
        .ex_we(ex_we[11]),
        .ex_wr_addr(ex_wr_addr[11]),
        .ex_wr_data(ex_wr_data[11]),
        .bz_we(bz_we[11]),
        .bz_wr_addr(bz_wr_addr[11]),
        .bz_wr_data(bz_wr_data[11])
    );

    bram_module #(
        .DEPTH(GRID_SIZE),
        .WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) bram_12 (
        .clk(clk),
        .rst(rst),
        .ey_rd_addr_0(ey_rd_addr_0[12]),
        .ey_rd_data_0(ey_rd_data_0[12]),
        .ey_rd_addr_1(ey_rd_addr_1[12]),
        .ey_rd_data_1(ey_rd_data_1[12]),
        .ex_rd_addr_0(ex_rd_addr_0[12]),
        .ex_rd_data_0(ex_rd_data_0[12]),
        .ex_rd_addr_1('0),
        .ex_rd_data_1(),
        .bz_rd_addr_0(bz_rd_addr_0[12]),
        .bz_rd_data_0(bz_rd_data_0[12]),
        .bz_rd_addr_1(bz_rd_addr_1[12]),
        .bz_rd_data_1(bz_rd_data_1[12]),
        .ey_we(ey_we[12]),
        .ey_wr_addr(ey_wr_addr[12]),
        .ey_wr_data(ey_wr_data[12]),
        .ex_we(ex_we[12]),
        .ex_wr_addr(ex_wr_addr[12]),
        .ex_wr_data(ex_wr_data[12]),
        .bz_we(bz_we[12]),
        .bz_wr_addr(bz_wr_addr[12]),
        .bz_wr_data(bz_wr_data[12])
    );

    bram_module #(
        .DEPTH(GRID_SIZE),
        .WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) bram_13 (
        .clk(clk),
        .rst(rst),
        .ey_rd_addr_0(ey_rd_addr_0[13]),
        .ey_rd_data_0(ey_rd_data_0[13]),
        .ey_rd_addr_1(ey_rd_addr_1[13]),
        .ey_rd_data_1(ey_rd_data_1[13]),
        .ex_rd_addr_0(ex_rd_addr_0[13]),
        .ex_rd_data_0(ex_rd_data_0[13]),
        .ex_rd_addr_1('0),
        .ex_rd_data_1(),
        .bz_rd_addr_0(bz_rd_addr_0[13]),
        .bz_rd_data_0(bz_rd_data_0[13]),
        .bz_rd_addr_1(bz_rd_addr_1[13]),
        .bz_rd_data_1(bz_rd_data_1[13]),
        .ey_we(ey_we[13]),
        .ey_wr_addr(ey_wr_addr[13]),
        .ey_wr_data(ey_wr_data[13]),
        .ex_we(ex_we[13]),
        .ex_wr_addr(ex_wr_addr[13]),
        .ex_wr_data(ex_wr_data[13]),
        .bz_we(bz_we[13]),
        .bz_wr_addr(bz_wr_addr[13]),
        .bz_wr_data(bz_wr_data[13])
    );

    bram_module #(
        .DEPTH(GRID_SIZE),
        .WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) bram_14 (
        .clk(clk),
        .rst(rst),
        .ey_rd_addr_0(ey_rd_addr_0[14]),
        .ey_rd_data_0(ey_rd_data_0[14]),
        .ey_rd_addr_1(ey_rd_addr_1[14]),
        .ey_rd_data_1(ey_rd_data_1[14]),
        .ex_rd_addr_0(ex_rd_addr_0[14]),
        .ex_rd_data_0(ex_rd_data_0[14]),
        .ex_rd_addr_1('0),
        .ex_rd_data_1(),
        .bz_rd_addr_0(bz_rd_addr_0[14]),
        .bz_rd_data_0(bz_rd_data_0[14]),
        .bz_rd_addr_1(bz_rd_addr_1[14]),
        .bz_rd_data_1(bz_rd_data_1[14]),
        .ey_we(ey_we[14]),
        .ey_wr_addr(ey_wr_addr[14]),
        .ey_wr_data(ey_wr_data[14]),
        .ex_we(ex_we[14]),
        .ex_wr_addr(ex_wr_addr[14]),
        .ex_wr_data(ex_wr_data[14]),
        .bz_we(bz_we[14]),
        .bz_wr_addr(bz_wr_addr[14]),
        .bz_wr_data(bz_wr_data[14])
    );

    bram_module #(
        .DEPTH(GRID_SIZE),
        .WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) bram_15 (
        .clk(clk),
        .rst(rst),
        .ey_rd_addr_0(ey_rd_addr_0[15]),
        .ey_rd_data_0(ey_rd_data_0[15]),
        .ey_rd_addr_1(ey_rd_addr_1[15]),
        .ey_rd_data_1(ey_rd_data_1[15]),
        .ex_rd_addr_0(ex_rd_addr_0[15]),
        .ex_rd_data_0(ex_rd_data_0[15]),
        .ex_rd_addr_1('0),
        .ex_rd_data_1(),
        .bz_rd_addr_0(bz_rd_addr_0[15]),
        .bz_rd_data_0(bz_rd_data_0[15]),
        .bz_rd_addr_1(bz_rd_addr_1[15]),
        .bz_rd_data_1(bz_rd_data_1[15]),
        .ey_we(ey_we[15]),
        .ey_wr_addr(ey_wr_addr[15]),
        .ey_wr_data(ey_wr_data[15]),
        .ex_we(ex_we[15]),
        .ex_wr_addr(ex_wr_addr[15]),
        .ex_wr_data(ex_wr_data[15]),
        .bz_we(bz_we[15]),
        .bz_wr_addr(bz_wr_addr[15]),
        .bz_wr_data(bz_wr_data[15])
    );

    fdtd_solver #(
        .TOTAL_ROWS(TOTAL_ROWS),
        .ROWS(ROWS),
        .COLUMNS(COLUMNS),
        .ROW_OFFSET(0),
        .FIRST_LANE(1),
        .LAST_LANE(0),
        .CELL_WIDTH(CELL_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .PML_SIZE(PML_SIZE)
    ) solver_0 (
        .clk(clk),
        .rst(rst),
        .source_in(source_in),
        .source_valid(source_valid && source_lane == 4'd0),
        .source_addr(local_source_addr),
        .ey_rd_addr(slv_ey_rd_addr[0]),
        .ey_rd_dout(ey_rd_data_0[0]),
        .ey_wr_addr(slv_ey_wr_addr[0]),
        .ey_wr_data(slv_ey_wr_data[0]),
        .ey_we(slv_ey_we[0]),
        .ex_rd_addr(slv_ex_rd_addr[0]),
        .ex_rd_dout(ex_rd_data_0[0]),
        .ex_wr_addr(slv_ex_wr_addr[0]),
        .ex_wr_data(slv_ex_wr_data[0]),
        .ex_we(slv_ex_we[0]),
        .bz_rd_addr(slv_bz_rd_addr[0]),
        .bz_rd_dout(bz_rd_data_0[0]),
        .bz_wr_addr(slv_bz_wr_addr[0]),
        .bz_wr_data(slv_bz_wr_data[0]),
        .bz_we(slv_bz_we[0]),
        .bz_adj_rd_addr(slv_bz_adj_rd_addr[0]),
        .bz_adj_dout(slv_bz_adj_dout[0]),
        .ey_adj_rd_addr(slv_ey_adj_rd_addr[0]),
        .ey_adj_dout(slv_ey_adj_dout[0]),
        .solver_enable(solver_enable),
        .solver_done(slv_done[0]),
        .current_row(slv_current_row[0]),
        .current_col(slv_current_col[0]),
        .e_phase(slv_e_phase[0])
    );

    fdtd_solver #(
        .TOTAL_ROWS(TOTAL_ROWS),
        .ROWS(ROWS),
        .COLUMNS(COLUMNS),
        .ROW_OFFSET(ROWS),
        .FIRST_LANE(0),
        .LAST_LANE(0),
        .CELL_WIDTH(CELL_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .PML_SIZE(PML_SIZE)
    ) solver_1 (
        .clk(clk),
        .rst(rst),
        .source_in(source_in),
        .source_valid(source_valid && source_lane == 4'd1),
        .source_addr(local_source_addr),
        .ey_rd_addr(slv_ey_rd_addr[1]),
        .ey_rd_dout(ey_rd_data_0[1]),
        .ey_wr_addr(slv_ey_wr_addr[1]),
        .ey_wr_data(slv_ey_wr_data[1]),
        .ey_we(slv_ey_we[1]),
        .ex_rd_addr(slv_ex_rd_addr[1]),
        .ex_rd_dout(ex_rd_data_0[1]),
        .ex_wr_addr(slv_ex_wr_addr[1]),
        .ex_wr_data(slv_ex_wr_data[1]),
        .ex_we(slv_ex_we[1]),
        .bz_rd_addr(slv_bz_rd_addr[1]),
        .bz_rd_dout(bz_rd_data_0[1]),
        .bz_wr_addr(slv_bz_wr_addr[1]),
        .bz_wr_data(slv_bz_wr_data[1]),
        .bz_we(slv_bz_we[1]),
        .bz_adj_rd_addr(slv_bz_adj_rd_addr[1]),
        .bz_adj_dout(slv_bz_adj_dout[1]),
        .ey_adj_rd_addr(slv_ey_adj_rd_addr[1]),
        .ey_adj_dout(slv_ey_adj_dout[1]),
        .solver_enable(solver_enable),
        .solver_done(slv_done[1]),
        .current_row(slv_current_row[1]),
        .current_col(slv_current_col[1]),
        .e_phase(slv_e_phase[1])
    );

    fdtd_solver #(
        .TOTAL_ROWS(TOTAL_ROWS),
        .ROWS(ROWS),
        .COLUMNS(COLUMNS),
        .ROW_OFFSET(2*ROWS),
        .FIRST_LANE(0),
        .LAST_LANE(0),
        .CELL_WIDTH(CELL_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .PML_SIZE(PML_SIZE)
    ) solver_2 (
        .clk(clk),
        .rst(rst),
        .source_in(source_in),
        .source_valid(source_valid && source_lane == 4'd2),
        .source_addr(local_source_addr),
        .ey_rd_addr(slv_ey_rd_addr[2]),
        .ey_rd_dout(ey_rd_data_0[2]),
        .ey_wr_addr(slv_ey_wr_addr[2]),
        .ey_wr_data(slv_ey_wr_data[2]),
        .ey_we(slv_ey_we[2]),
        .ex_rd_addr(slv_ex_rd_addr[2]),
        .ex_rd_dout(ex_rd_data_0[2]),
        .ex_wr_addr(slv_ex_wr_addr[2]),
        .ex_wr_data(slv_ex_wr_data[2]),
        .ex_we(slv_ex_we[2]),
        .bz_rd_addr(slv_bz_rd_addr[2]),
        .bz_rd_dout(bz_rd_data_0[2]),
        .bz_wr_addr(slv_bz_wr_addr[2]),
        .bz_wr_data(slv_bz_wr_data[2]),
        .bz_we(slv_bz_we[2]),
        .bz_adj_rd_addr(slv_bz_adj_rd_addr[2]),
        .bz_adj_dout(slv_bz_adj_dout[2]),
        .ey_adj_rd_addr(slv_ey_adj_rd_addr[2]),
        .ey_adj_dout(slv_ey_adj_dout[2]),
        .solver_enable(solver_enable),
        .solver_done(slv_done[2]),
        .current_row(slv_current_row[2]),
        .current_col(slv_current_col[2]),
        .e_phase(slv_e_phase[2])
    );

    fdtd_solver #(
        .TOTAL_ROWS(TOTAL_ROWS),
        .ROWS(ROWS),
        .COLUMNS(COLUMNS),
        .ROW_OFFSET(3*ROWS),
        .FIRST_LANE(0),
        .LAST_LANE(0),
        .CELL_WIDTH(CELL_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .PML_SIZE(PML_SIZE)
    ) solver_3 (
        .clk(clk),
        .rst(rst),
        .source_in(source_in),
        .source_valid(source_valid && source_lane == 4'd3),
        .source_addr(local_source_addr),
        .ey_rd_addr(slv_ey_rd_addr[3]),
        .ey_rd_dout(ey_rd_data_0[3]),
        .ey_wr_addr(slv_ey_wr_addr[3]),
        .ey_wr_data(slv_ey_wr_data[3]),
        .ey_we(slv_ey_we[3]),
        .ex_rd_addr(slv_ex_rd_addr[3]),
        .ex_rd_dout(ex_rd_data_0[3]),
        .ex_wr_addr(slv_ex_wr_addr[3]),
        .ex_wr_data(slv_ex_wr_data[3]),
        .ex_we(slv_ex_we[3]),
        .bz_rd_addr(slv_bz_rd_addr[3]),
        .bz_rd_dout(bz_rd_data_0[3]),
        .bz_wr_addr(slv_bz_wr_addr[3]),
        .bz_wr_data(slv_bz_wr_data[3]),
        .bz_we(slv_bz_we[3]),
        .bz_adj_rd_addr(slv_bz_adj_rd_addr[3]),
        .bz_adj_dout(slv_bz_adj_dout[3]),
        .ey_adj_rd_addr(slv_ey_adj_rd_addr[3]),
        .ey_adj_dout(slv_ey_adj_dout[3]),
        .solver_enable(solver_enable),
        .solver_done(slv_done[3]),
        .current_row(slv_current_row[3]),
        .current_col(slv_current_col[3]),
        .e_phase(slv_e_phase[3])
    );

    fdtd_solver #(
        .TOTAL_ROWS(TOTAL_ROWS),
        .ROWS(ROWS),
        .COLUMNS(COLUMNS),
        .ROW_OFFSET(4*ROWS),
        .FIRST_LANE(0),
        .LAST_LANE(0),
        .CELL_WIDTH(CELL_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .PML_SIZE(PML_SIZE)
    ) solver_4 (
        .clk(clk),
        .rst(rst),
        .source_in(source_in),
        .source_valid(source_valid && source_lane == 4'd4),
        .source_addr(local_source_addr),
        .ey_rd_addr(slv_ey_rd_addr[4]),
        .ey_rd_dout(ey_rd_data_0[4]),
        .ey_wr_addr(slv_ey_wr_addr[4]),
        .ey_wr_data(slv_ey_wr_data[4]),
        .ey_we(slv_ey_we[4]),
        .ex_rd_addr(slv_ex_rd_addr[4]),
        .ex_rd_dout(ex_rd_data_0[4]),
        .ex_wr_addr(slv_ex_wr_addr[4]),
        .ex_wr_data(slv_ex_wr_data[4]),
        .ex_we(slv_ex_we[4]),
        .bz_rd_addr(slv_bz_rd_addr[4]),
        .bz_rd_dout(bz_rd_data_0[4]),
        .bz_wr_addr(slv_bz_wr_addr[4]),
        .bz_wr_data(slv_bz_wr_data[4]),
        .bz_we(slv_bz_we[4]),
        .bz_adj_rd_addr(slv_bz_adj_rd_addr[4]),
        .bz_adj_dout(slv_bz_adj_dout[4]),
        .ey_adj_rd_addr(slv_ey_adj_rd_addr[4]),
        .ey_adj_dout(slv_ey_adj_dout[4]),
        .solver_enable(solver_enable),
        .solver_done(slv_done[4]),
        .current_row(slv_current_row[4]),
        .current_col(slv_current_col[4]),
        .e_phase(slv_e_phase[4])
    );

    fdtd_solver #(
        .TOTAL_ROWS(TOTAL_ROWS),
        .ROWS(ROWS),
        .COLUMNS(COLUMNS),
        .ROW_OFFSET(5*ROWS),
        .FIRST_LANE(0),
        .LAST_LANE(0),
        .CELL_WIDTH(CELL_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .PML_SIZE(PML_SIZE)
    ) solver_5 (
        .clk(clk),
        .rst(rst),
        .source_in(source_in),
        .source_valid(source_valid && source_lane == 4'd5),
        .source_addr(local_source_addr),
        .ey_rd_addr(slv_ey_rd_addr[5]),
        .ey_rd_dout(ey_rd_data_0[5]),
        .ey_wr_addr(slv_ey_wr_addr[5]),
        .ey_wr_data(slv_ey_wr_data[5]),
        .ey_we(slv_ey_we[5]),
        .ex_rd_addr(slv_ex_rd_addr[5]),
        .ex_rd_dout(ex_rd_data_0[5]),
        .ex_wr_addr(slv_ex_wr_addr[5]),
        .ex_wr_data(slv_ex_wr_data[5]),
        .ex_we(slv_ex_we[5]),
        .bz_rd_addr(slv_bz_rd_addr[5]),
        .bz_rd_dout(bz_rd_data_0[5]),
        .bz_wr_addr(slv_bz_wr_addr[5]),
        .bz_wr_data(slv_bz_wr_data[5]),
        .bz_we(slv_bz_we[5]),
        .bz_adj_rd_addr(slv_bz_adj_rd_addr[5]),
        .bz_adj_dout(slv_bz_adj_dout[5]),
        .ey_adj_rd_addr(slv_ey_adj_rd_addr[5]),
        .ey_adj_dout(slv_ey_adj_dout[5]),
        .solver_enable(solver_enable),
        .solver_done(slv_done[5]),
        .current_row(slv_current_row[5]),
        .current_col(slv_current_col[5]),
        .e_phase(slv_e_phase[5])
    );

    fdtd_solver #(
        .TOTAL_ROWS(TOTAL_ROWS),
        .ROWS(ROWS),
        .COLUMNS(COLUMNS),
        .ROW_OFFSET(6*ROWS),
        .FIRST_LANE(0),
        .LAST_LANE(0),
        .CELL_WIDTH(CELL_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .PML_SIZE(PML_SIZE)
    ) solver_6 (
        .clk(clk),
        .rst(rst),
        .source_in(source_in),
        .source_valid(source_valid && source_lane == 4'd6),
        .source_addr(local_source_addr),
        .ey_rd_addr(slv_ey_rd_addr[6]),
        .ey_rd_dout(ey_rd_data_0[6]),
        .ey_wr_addr(slv_ey_wr_addr[6]),
        .ey_wr_data(slv_ey_wr_data[6]),
        .ey_we(slv_ey_we[6]),
        .ex_rd_addr(slv_ex_rd_addr[6]),
        .ex_rd_dout(ex_rd_data_0[6]),
        .ex_wr_addr(slv_ex_wr_addr[6]),
        .ex_wr_data(slv_ex_wr_data[6]),
        .ex_we(slv_ex_we[6]),
        .bz_rd_addr(slv_bz_rd_addr[6]),
        .bz_rd_dout(bz_rd_data_0[6]),
        .bz_wr_addr(slv_bz_wr_addr[6]),
        .bz_wr_data(slv_bz_wr_data[6]),
        .bz_we(slv_bz_we[6]),
        .bz_adj_rd_addr(slv_bz_adj_rd_addr[6]),
        .bz_adj_dout(slv_bz_adj_dout[6]),
        .ey_adj_rd_addr(slv_ey_adj_rd_addr[6]),
        .ey_adj_dout(slv_ey_adj_dout[6]),
        .solver_enable(solver_enable),
        .solver_done(slv_done[6]),
        .current_row(slv_current_row[6]),
        .current_col(slv_current_col[6]),
        .e_phase(slv_e_phase[6])
    );

    fdtd_solver #(
        .TOTAL_ROWS(TOTAL_ROWS),
        .ROWS(ROWS),
        .COLUMNS(COLUMNS),
        .ROW_OFFSET(7*ROWS),
        .FIRST_LANE(0),
        .LAST_LANE(0),
        .CELL_WIDTH(CELL_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .PML_SIZE(PML_SIZE)
    ) solver_7 (
        .clk(clk),
        .rst(rst),
        .source_in(source_in),
        .source_valid(source_valid && source_lane == 4'd7),
        .source_addr(local_source_addr),
        .ey_rd_addr(slv_ey_rd_addr[7]),
        .ey_rd_dout(ey_rd_data_0[7]),
        .ey_wr_addr(slv_ey_wr_addr[7]),
        .ey_wr_data(slv_ey_wr_data[7]),
        .ey_we(slv_ey_we[7]),
        .ex_rd_addr(slv_ex_rd_addr[7]),
        .ex_rd_dout(ex_rd_data_0[7]),
        .ex_wr_addr(slv_ex_wr_addr[7]),
        .ex_wr_data(slv_ex_wr_data[7]),
        .ex_we(slv_ex_we[7]),
        .bz_rd_addr(slv_bz_rd_addr[7]),
        .bz_rd_dout(bz_rd_data_0[7]),
        .bz_wr_addr(slv_bz_wr_addr[7]),
        .bz_wr_data(slv_bz_wr_data[7]),
        .bz_we(slv_bz_we[7]),
        .bz_adj_rd_addr(slv_bz_adj_rd_addr[7]),
        .bz_adj_dout(slv_bz_adj_dout[7]),
        .ey_adj_rd_addr(slv_ey_adj_rd_addr[7]),
        .ey_adj_dout(slv_ey_adj_dout[7]),
        .solver_enable(solver_enable),
        .solver_done(slv_done[7]),
        .current_row(slv_current_row[7]),
        .current_col(slv_current_col[7]),
        .e_phase(slv_e_phase[7])
    );

    fdtd_solver #(
        .TOTAL_ROWS(TOTAL_ROWS),
        .ROWS(ROWS),
        .COLUMNS(COLUMNS),
        .ROW_OFFSET(8*ROWS),
        .FIRST_LANE(0),
        .LAST_LANE(0),
        .CELL_WIDTH(CELL_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .PML_SIZE(PML_SIZE)
    ) solver_8 (
        .clk(clk),
        .rst(rst),
        .source_in(source_in),
        .source_valid(source_valid && source_lane == 4'd8),
        .source_addr(local_source_addr),
        .ey_rd_addr(slv_ey_rd_addr[8]),
        .ey_rd_dout(ey_rd_data_0[8]),
        .ey_wr_addr(slv_ey_wr_addr[8]),
        .ey_wr_data(slv_ey_wr_data[8]),
        .ey_we(slv_ey_we[8]),
        .ex_rd_addr(slv_ex_rd_addr[8]),
        .ex_rd_dout(ex_rd_data_0[8]),
        .ex_wr_addr(slv_ex_wr_addr[8]),
        .ex_wr_data(slv_ex_wr_data[8]),
        .ex_we(slv_ex_we[8]),
        .bz_rd_addr(slv_bz_rd_addr[8]),
        .bz_rd_dout(bz_rd_data_0[8]),
        .bz_wr_addr(slv_bz_wr_addr[8]),
        .bz_wr_data(slv_bz_wr_data[8]),
        .bz_we(slv_bz_we[8]),
        .bz_adj_rd_addr(slv_bz_adj_rd_addr[8]),
        .bz_adj_dout(slv_bz_adj_dout[8]),
        .ey_adj_rd_addr(slv_ey_adj_rd_addr[8]),
        .ey_adj_dout(slv_ey_adj_dout[8]),
        .solver_enable(solver_enable),
        .solver_done(slv_done[8]),
        .current_row(slv_current_row[8]),
        .current_col(slv_current_col[8]),
        .e_phase(slv_e_phase[8])
    );

    fdtd_solver #(
        .TOTAL_ROWS(TOTAL_ROWS),
        .ROWS(ROWS),
        .COLUMNS(COLUMNS),
        .ROW_OFFSET(9*ROWS),
        .FIRST_LANE(0),
        .LAST_LANE(0),
        .CELL_WIDTH(CELL_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .PML_SIZE(PML_SIZE)
    ) solver_9 (
        .clk(clk),
        .rst(rst),
        .source_in(source_in),
        .source_valid(source_valid && source_lane == 4'd9),
        .source_addr(local_source_addr),
        .ey_rd_addr(slv_ey_rd_addr[9]),
        .ey_rd_dout(ey_rd_data_0[9]),
        .ey_wr_addr(slv_ey_wr_addr[9]),
        .ey_wr_data(slv_ey_wr_data[9]),
        .ey_we(slv_ey_we[9]),
        .ex_rd_addr(slv_ex_rd_addr[9]),
        .ex_rd_dout(ex_rd_data_0[9]),
        .ex_wr_addr(slv_ex_wr_addr[9]),
        .ex_wr_data(slv_ex_wr_data[9]),
        .ex_we(slv_ex_we[9]),
        .bz_rd_addr(slv_bz_rd_addr[9]),
        .bz_rd_dout(bz_rd_data_0[9]),
        .bz_wr_addr(slv_bz_wr_addr[9]),
        .bz_wr_data(slv_bz_wr_data[9]),
        .bz_we(slv_bz_we[9]),
        .bz_adj_rd_addr(slv_bz_adj_rd_addr[9]),
        .bz_adj_dout(slv_bz_adj_dout[9]),
        .ey_adj_rd_addr(slv_ey_adj_rd_addr[9]),
        .ey_adj_dout(slv_ey_adj_dout[9]),
        .solver_enable(solver_enable),
        .solver_done(slv_done[9]),
        .current_row(slv_current_row[9]),
        .current_col(slv_current_col[9]),
        .e_phase(slv_e_phase[9])
    );

    fdtd_solver #(
        .TOTAL_ROWS(TOTAL_ROWS),
        .ROWS(ROWS),
        .COLUMNS(COLUMNS),
        .ROW_OFFSET(10*ROWS),
        .FIRST_LANE(0),
        .LAST_LANE(0),
        .CELL_WIDTH(CELL_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .PML_SIZE(PML_SIZE)
    ) solver_10 (
        .clk(clk),
        .rst(rst),
        .source_in(source_in),
        .source_valid(source_valid && source_lane == 4'd10),
        .source_addr(local_source_addr),
        .ey_rd_addr(slv_ey_rd_addr[10]),
        .ey_rd_dout(ey_rd_data_0[10]),
        .ey_wr_addr(slv_ey_wr_addr[10]),
        .ey_wr_data(slv_ey_wr_data[10]),
        .ey_we(slv_ey_we[10]),
        .ex_rd_addr(slv_ex_rd_addr[10]),
        .ex_rd_dout(ex_rd_data_0[10]),
        .ex_wr_addr(slv_ex_wr_addr[10]),
        .ex_wr_data(slv_ex_wr_data[10]),
        .ex_we(slv_ex_we[10]),
        .bz_rd_addr(slv_bz_rd_addr[10]),
        .bz_rd_dout(bz_rd_data_0[10]),
        .bz_wr_addr(slv_bz_wr_addr[10]),
        .bz_wr_data(slv_bz_wr_data[10]),
        .bz_we(slv_bz_we[10]),
        .bz_adj_rd_addr(slv_bz_adj_rd_addr[10]),
        .bz_adj_dout(slv_bz_adj_dout[10]),
        .ey_adj_rd_addr(slv_ey_adj_rd_addr[10]),
        .ey_adj_dout(slv_ey_adj_dout[10]),
        .solver_enable(solver_enable),
        .solver_done(slv_done[10]),
        .current_row(slv_current_row[10]),
        .current_col(slv_current_col[10]),
        .e_phase(slv_e_phase[10])
    );

    fdtd_solver #(
        .TOTAL_ROWS(TOTAL_ROWS),
        .ROWS(ROWS),
        .COLUMNS(COLUMNS),
        .ROW_OFFSET(11*ROWS),
        .FIRST_LANE(0),
        .LAST_LANE(0),
        .CELL_WIDTH(CELL_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .PML_SIZE(PML_SIZE)
    ) solver_11 (
        .clk(clk),
        .rst(rst),
        .source_in(source_in),
        .source_valid(source_valid && source_lane == 4'd11),
        .source_addr(local_source_addr),
        .ey_rd_addr(slv_ey_rd_addr[11]),
        .ey_rd_dout(ey_rd_data_0[11]),
        .ey_wr_addr(slv_ey_wr_addr[11]),
        .ey_wr_data(slv_ey_wr_data[11]),
        .ey_we(slv_ey_we[11]),
        .ex_rd_addr(slv_ex_rd_addr[11]),
        .ex_rd_dout(ex_rd_data_0[11]),
        .ex_wr_addr(slv_ex_wr_addr[11]),
        .ex_wr_data(slv_ex_wr_data[11]),
        .ex_we(slv_ex_we[11]),
        .bz_rd_addr(slv_bz_rd_addr[11]),
        .bz_rd_dout(bz_rd_data_0[11]),
        .bz_wr_addr(slv_bz_wr_addr[11]),
        .bz_wr_data(slv_bz_wr_data[11]),
        .bz_we(slv_bz_we[11]),
        .bz_adj_rd_addr(slv_bz_adj_rd_addr[11]),
        .bz_adj_dout(slv_bz_adj_dout[11]),
        .ey_adj_rd_addr(slv_ey_adj_rd_addr[11]),
        .ey_adj_dout(slv_ey_adj_dout[11]),
        .solver_enable(solver_enable),
        .solver_done(slv_done[11]),
        .current_row(slv_current_row[11]),
        .current_col(slv_current_col[11]),
        .e_phase(slv_e_phase[11])
    );

    fdtd_solver #(
        .TOTAL_ROWS(TOTAL_ROWS),
        .ROWS(ROWS),
        .COLUMNS(COLUMNS),
        .ROW_OFFSET(12*ROWS),
        .FIRST_LANE(0),
        .LAST_LANE(0),
        .CELL_WIDTH(CELL_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .PML_SIZE(PML_SIZE)
    ) solver_12 (
        .clk(clk),
        .rst(rst),
        .source_in(source_in),
        .source_valid(source_valid && source_lane == 4'd12),
        .source_addr(local_source_addr),
        .ey_rd_addr(slv_ey_rd_addr[12]),
        .ey_rd_dout(ey_rd_data_0[12]),
        .ey_wr_addr(slv_ey_wr_addr[12]),
        .ey_wr_data(slv_ey_wr_data[12]),
        .ey_we(slv_ey_we[12]),
        .ex_rd_addr(slv_ex_rd_addr[12]),
        .ex_rd_dout(ex_rd_data_0[12]),
        .ex_wr_addr(slv_ex_wr_addr[12]),
        .ex_wr_data(slv_ex_wr_data[12]),
        .ex_we(slv_ex_we[12]),
        .bz_rd_addr(slv_bz_rd_addr[12]),
        .bz_rd_dout(bz_rd_data_0[12]),
        .bz_wr_addr(slv_bz_wr_addr[12]),
        .bz_wr_data(slv_bz_wr_data[12]),
        .bz_we(slv_bz_we[12]),
        .bz_adj_rd_addr(slv_bz_adj_rd_addr[12]),
        .bz_adj_dout(slv_bz_adj_dout[12]),
        .ey_adj_rd_addr(slv_ey_adj_rd_addr[12]),
        .ey_adj_dout(slv_ey_adj_dout[12]),
        .solver_enable(solver_enable),
        .solver_done(slv_done[12]),
        .current_row(slv_current_row[12]),
        .current_col(slv_current_col[12]),
        .e_phase(slv_e_phase[12])
    );

    fdtd_solver #(
        .TOTAL_ROWS(TOTAL_ROWS),
        .ROWS(ROWS),
        .COLUMNS(COLUMNS),
        .ROW_OFFSET(13*ROWS),
        .FIRST_LANE(0),
        .LAST_LANE(0),
        .CELL_WIDTH(CELL_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .PML_SIZE(PML_SIZE)
    ) solver_13 (
        .clk(clk),
        .rst(rst),
        .source_in(source_in),
        .source_valid(source_valid && source_lane == 4'd13),
        .source_addr(local_source_addr),
        .ey_rd_addr(slv_ey_rd_addr[13]),
        .ey_rd_dout(ey_rd_data_0[13]),
        .ey_wr_addr(slv_ey_wr_addr[13]),
        .ey_wr_data(slv_ey_wr_data[13]),
        .ey_we(slv_ey_we[13]),
        .ex_rd_addr(slv_ex_rd_addr[13]),
        .ex_rd_dout(ex_rd_data_0[13]),
        .ex_wr_addr(slv_ex_wr_addr[13]),
        .ex_wr_data(slv_ex_wr_data[13]),
        .ex_we(slv_ex_we[13]),
        .bz_rd_addr(slv_bz_rd_addr[13]),
        .bz_rd_dout(bz_rd_data_0[13]),
        .bz_wr_addr(slv_bz_wr_addr[13]),
        .bz_wr_data(slv_bz_wr_data[13]),
        .bz_we(slv_bz_we[13]),
        .bz_adj_rd_addr(slv_bz_adj_rd_addr[13]),
        .bz_adj_dout(slv_bz_adj_dout[13]),
        .ey_adj_rd_addr(slv_ey_adj_rd_addr[13]),
        .ey_adj_dout(slv_ey_adj_dout[13]),
        .solver_enable(solver_enable),
        .solver_done(slv_done[13]),
        .current_row(slv_current_row[13]),
        .current_col(slv_current_col[13]),
        .e_phase(slv_e_phase[13])
    );

    fdtd_solver #(
        .TOTAL_ROWS(TOTAL_ROWS),
        .ROWS(ROWS),
        .COLUMNS(COLUMNS),
        .ROW_OFFSET(14*ROWS),
        .FIRST_LANE(0),
        .LAST_LANE(0),
        .CELL_WIDTH(CELL_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .PML_SIZE(PML_SIZE)
    ) solver_14 (
        .clk(clk),
        .rst(rst),
        .source_in(source_in),
        .source_valid(source_valid && source_lane == 4'd14),
        .source_addr(local_source_addr),
        .ey_rd_addr(slv_ey_rd_addr[14]),
        .ey_rd_dout(ey_rd_data_0[14]),
        .ey_wr_addr(slv_ey_wr_addr[14]),
        .ey_wr_data(slv_ey_wr_data[14]),
        .ey_we(slv_ey_we[14]),
        .ex_rd_addr(slv_ex_rd_addr[14]),
        .ex_rd_dout(ex_rd_data_0[14]),
        .ex_wr_addr(slv_ex_wr_addr[14]),
        .ex_wr_data(slv_ex_wr_data[14]),
        .ex_we(slv_ex_we[14]),
        .bz_rd_addr(slv_bz_rd_addr[14]),
        .bz_rd_dout(bz_rd_data_0[14]),
        .bz_wr_addr(slv_bz_wr_addr[14]),
        .bz_wr_data(slv_bz_wr_data[14]),
        .bz_we(slv_bz_we[14]),
        .bz_adj_rd_addr(slv_bz_adj_rd_addr[14]),
        .bz_adj_dout(slv_bz_adj_dout[14]),
        .ey_adj_rd_addr(slv_ey_adj_rd_addr[14]),
        .ey_adj_dout(slv_ey_adj_dout[14]),
        .solver_enable(solver_enable),
        .solver_done(slv_done[14]),
        .current_row(slv_current_row[14]),
        .current_col(slv_current_col[14]),
        .e_phase(slv_e_phase[14])
    );

    fdtd_solver #(
        .TOTAL_ROWS(TOTAL_ROWS),
        .ROWS(ROWS),
        .COLUMNS(COLUMNS),
        .ROW_OFFSET(15*ROWS),
        .FIRST_LANE(0),
        .LAST_LANE(1),
        .CELL_WIDTH(CELL_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .PML_SIZE(PML_SIZE)
    ) solver_15 (
        .clk(clk),
        .rst(rst),
        .source_in(source_in),
        .source_valid(source_valid && source_lane == 4'd15),
        .source_addr(local_source_addr),
        .ey_rd_addr(slv_ey_rd_addr[15]),
        .ey_rd_dout(ey_rd_data_0[15]),
        .ey_wr_addr(slv_ey_wr_addr[15]),
        .ey_wr_data(slv_ey_wr_data[15]),
        .ey_we(slv_ey_we[15]),
        .ex_rd_addr(slv_ex_rd_addr[15]),
        .ex_rd_dout(ex_rd_data_0[15]),
        .ex_wr_addr(slv_ex_wr_addr[15]),
        .ex_wr_data(slv_ex_wr_data[15]),
        .ex_we(slv_ex_we[15]),
        .bz_rd_addr(slv_bz_rd_addr[15]),
        .bz_rd_dout(bz_rd_data_0[15]),
        .bz_wr_addr(slv_bz_wr_addr[15]),
        .bz_wr_data(slv_bz_wr_data[15]),
        .bz_we(slv_bz_we[15]),
        .bz_adj_rd_addr(slv_bz_adj_rd_addr[15]),
        .bz_adj_dout(slv_bz_adj_dout[15]),
        .ey_adj_rd_addr(slv_ey_adj_rd_addr[15]),
        .ey_adj_dout(slv_ey_adj_dout[15]),
        .solver_enable(solver_enable),
        .solver_done(slv_done[15]),
        .current_row(slv_current_row[15]),
        .current_col(slv_current_col[15]),
        .e_phase(slv_e_phase[15])
    );

endmodule
