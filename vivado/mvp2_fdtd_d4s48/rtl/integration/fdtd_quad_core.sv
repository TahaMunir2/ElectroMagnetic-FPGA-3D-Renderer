`timescale 1ns/1ps

module fdtd_quad_core #(
    parameter LANES = 4,
    parameter TOTAL_ROWS = 64,
    parameter ROWS = TOTAL_ROWS / LANES,
    parameter COLUMNS = 64,
    parameter CELL_WIDTH = 6,
    parameter DATA_WIDTH = 16,
    parameter PML_SIZE = 6
)(
    input  wire clk,
    input  wire rst,
    input  wire [DATA_WIDTH-1:0] source_in,
    input  wire source_valid,
    input  wire [2*CELL_WIDTH-1:0] source_addr,
    input  wire source_bz,                     // 0=Ey dipole, 1=Bz monopole
    input  wire solver_enable,
    output logic solver_done,

    // -------- Magnitude read-back (borrows field read port 0 when solver idle) --
    //  Present a unified 0..4095 global address; returns the field at that cell.
    input  wire                    mag_active,
    input  wire [2*CELL_WIDTH-1:0] mag_addr,    // global 0..4095
    output logic [DATA_WIDTH-1:0]  mag_ey,
    output logic [DATA_WIDTH-1:0]  mag_ex,
    output logic [DATA_WIDTH-1:0]  mag_bz,

    // -------- Field clear (overrides the write ports, all lanes in parallel) ----
    input  wire                    clear_active,
    input  wire [2*CELL_WIDTH-1:0] clear_addr   // local 0..ROWS*COLUMNS-1
);

    localparam GRID_SIZE = ROWS * COLUMNS;
    localparam ADDR_WIDTH = 2 * CELL_WIDTH;

    // Magnitude global address -> lane + local; field read port 0 is registered
    // (1 cycle), so select the lane one cycle after the address is issued.
    logic [1:0]            mag_lane;
    logic [ADDR_WIDTH-1:0] mag_local;
    assign mag_lane  = mag_addr / GRID_SIZE;
    assign mag_local = mag_addr - (mag_lane * GRID_SIZE);
    logic [1:0] mag_lane_d;
    always_ff @(posedge clk) mag_lane_d <= mag_lane;
    assign mag_ey = ey_rd_data_0[mag_lane_d];
    assign mag_ex = ex_rd_data_0[mag_lane_d];
    assign mag_bz = bz_rd_data_0[mag_lane_d];

    logic [1:0] source_lane;
    logic [ADDR_WIDTH-1:0] local_source_addr;

    assign source_lane = source_addr / GRID_SIZE;
    assign local_source_addr = source_addr - (source_lane * GRID_SIZE);

    logic [ADDR_WIDTH-1:0] ey_rd_addr_0 [3:0];
    logic [ADDR_WIDTH-1:0] ey_rd_addr_1 [3:0];
    logic [DATA_WIDTH-1:0] ey_rd_data_0 [3:0];
    logic [DATA_WIDTH-1:0] ey_rd_data_1 [3:0];
    logic ey_we [3:0];
    logic [ADDR_WIDTH-1:0] ey_wr_addr [3:0];
    logic [DATA_WIDTH-1:0] ey_wr_data [3:0];

    logic [ADDR_WIDTH-1:0] ex_rd_addr_0 [3:0];
    logic [DATA_WIDTH-1:0] ex_rd_data_0 [3:0];
    logic ex_we [3:0];
    logic [ADDR_WIDTH-1:0] ex_wr_addr [3:0];
    logic [DATA_WIDTH-1:0] ex_wr_data [3:0];

    logic [ADDR_WIDTH-1:0] bz_rd_addr_0 [3:0];
    logic [ADDR_WIDTH-1:0] bz_rd_addr_1 [3:0];
    logic [DATA_WIDTH-1:0] bz_rd_data_0 [3:0];
    logic [DATA_WIDTH-1:0] bz_rd_data_1 [3:0];
    logic bz_we [3:0];
    logic [ADDR_WIDTH-1:0] bz_wr_addr [3:0];
    logic [DATA_WIDTH-1:0] bz_wr_data [3:0];

    logic [ADDR_WIDTH-1:0] slv_ey_rd_addr [3:0];
    logic [ADDR_WIDTH-1:0] slv_ey_wr_addr [3:0];
    logic [DATA_WIDTH-1:0] slv_ey_wr_data [3:0];
    logic slv_ey_we [3:0];
    logic [ADDR_WIDTH-1:0] slv_ex_rd_addr [3:0];
    logic [ADDR_WIDTH-1:0] slv_ex_wr_addr [3:0];
    logic [DATA_WIDTH-1:0] slv_ex_wr_data [3:0];
    logic slv_ex_we [3:0];
    logic [ADDR_WIDTH-1:0] slv_bz_rd_addr [3:0];
    logic [ADDR_WIDTH-1:0] slv_bz_wr_addr [3:0];
    logic [DATA_WIDTH-1:0] slv_bz_wr_data [3:0];
    logic slv_bz_we [3:0];
    logic [ADDR_WIDTH-1:0] slv_bz_adj_rd_addr [3:0];
    logic [DATA_WIDTH-1:0] slv_bz_adj_dout [3:0];
    logic [ADDR_WIDTH-1:0] slv_ey_adj_rd_addr [3:0];
    logic [DATA_WIDTH-1:0] slv_ey_adj_dout [3:0];
    logic slv_done [3:0];
    logic [CELL_WIDTH-1:0] slv_current_row [3:0];
    logic [CELL_WIDTH-1:0] slv_current_col [3:0];
    logic slv_e_phase [3:0];

    logic [CELL_WIDTH-1:0] prev_row [3:0];
    logic prev_phase [3:0];

    always_ff @(posedge clk) begin
        prev_row[0] <= slv_current_row[0];
        prev_phase[0] <= slv_e_phase[0];
        prev_row[1] <= slv_current_row[1];
        prev_phase[1] <= slv_e_phase[1];
        prev_row[2] <= slv_current_row[2];
        prev_phase[2] <= slv_e_phase[2];
        prev_row[3] <= slv_current_row[3];
        prev_phase[3] <= slv_e_phase[3];
    end

    // Read port 0: solver drives it normally; the magnitude scanner borrows it
    // (same local address to all lanes; the right lane's output is selected by
    //  mag_lane_d above). genvar fan-out keeps it tidy.
    genvar L;
    generate
        for (L = 0; L < 4; L = L + 1) begin : g_rd0_mux
            assign ey_rd_addr_0[L] = mag_active ? mag_local : slv_ey_rd_addr[L];
            assign ex_rd_addr_0[L] = mag_active ? mag_local : slv_ex_rd_addr[L];
            assign bz_rd_addr_0[L] = mag_active ? mag_local : slv_bz_rd_addr[L];
        end
        // Write ports: solver drives them; field-clear overrides all lanes to 0.
        for (L = 0; L < 4; L = L + 1) begin : g_wr_mux
            assign ey_we[L]      = clear_active ? 1'b1       : slv_ey_we[L];
            assign ey_wr_addr[L] = clear_active ? clear_addr : slv_ey_wr_addr[L];
            assign ey_wr_data[L] = clear_active ? '0         : slv_ey_wr_data[L];
            assign ex_we[L]      = clear_active ? 1'b1       : slv_ex_we[L];
            assign ex_wr_addr[L] = clear_active ? clear_addr : slv_ex_wr_addr[L];
            assign ex_wr_data[L] = clear_active ? '0         : slv_ex_wr_data[L];
            assign bz_we[L]      = clear_active ? 1'b1       : slv_bz_we[L];
            assign bz_wr_addr[L] = clear_active ? clear_addr : slv_bz_wr_addr[L];
            assign bz_wr_data[L] = clear_active ? '0         : slv_bz_wr_data[L];
        end
    endgenerate

    always_comb begin
        bz_rd_addr_1[0] = slv_bz_adj_rd_addr[0];
        bz_rd_addr_1[1] = slv_bz_adj_rd_addr[1];
        bz_rd_addr_1[2] = slv_bz_adj_rd_addr[2];
        bz_rd_addr_1[3] = slv_bz_adj_rd_addr[3];
        ey_rd_addr_1[0] = slv_ey_adj_rd_addr[0];
        ey_rd_addr_1[1] = slv_ey_adj_rd_addr[1];
        ey_rd_addr_1[2] = slv_ey_adj_rd_addr[2];
        ey_rd_addr_1[3] = slv_ey_adj_rd_addr[3];

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
    end

    always_comb begin
        slv_bz_adj_dout[0] = bz_rd_data_1[0];
        slv_bz_adj_dout[1] = bz_rd_data_1[1];
        slv_bz_adj_dout[2] = bz_rd_data_1[2];
        slv_bz_adj_dout[3] = bz_rd_data_1[3];
        slv_ey_adj_dout[0] = ey_rd_data_1[0];
        slv_ey_adj_dout[1] = ey_rd_data_1[1];
        slv_ey_adj_dout[2] = ey_rd_data_1[2];
        slv_ey_adj_dout[3] = ey_rd_data_1[3];

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
    end

    assign solver_done = slv_done[0] & slv_done[1] & slv_done[2] & slv_done[3];

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
        .source_valid(source_valid && source_lane == 2'd0),
        .source_addr(local_source_addr),
        .source_bz(source_bz),
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
        .source_valid(source_valid && source_lane == 2'd1),
        .source_addr(local_source_addr),
        .source_bz(source_bz),
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
        .source_valid(source_valid && source_lane == 2'd2),
        .source_addr(local_source_addr),
        .source_bz(source_bz),
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
        .LAST_LANE(1),
        .CELL_WIDTH(CELL_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .PML_SIZE(PML_SIZE)
    ) solver_3 (
        .clk(clk),
        .rst(rst),
        .source_in(source_in),
        .source_valid(source_valid && source_lane == 2'd3),
        .source_addr(local_source_addr),
        .source_bz(source_bz),
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

endmodule
