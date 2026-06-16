`timescale 1ns/1ps

module fdtd_solver #(
    parameter LANES = 4,
    parameter TOTAL_ROWS = 64,
    parameter ROWS = TOTAL_ROWS / LANES,
    parameter COLUMNS = 64,
    parameter ROW_OFFSET = 0,
    parameter FIRST_LANE = 1,
    parameter LAST_LANE = 1,
    parameter CELL_WIDTH = 6,
    parameter DATA_WIDTH = 16,
    parameter PML_SIZE = 6
)(
    input  wire clk,
    input  wire rst,
    input  wire [DATA_WIDTH-1:0] source_in,
    input  wire                  source_valid,
    input  wire [2*CELL_WIDTH-1:0]  source_addr,
    output logic [2*CELL_WIDTH-1:0] ey_rd_addr,
    input  wire  [DATA_WIDTH-1:0]   ey_rd_dout,
    output logic [2*CELL_WIDTH-1:0] ey_wr_addr,
    output logic [DATA_WIDTH-1:0]   ey_wr_data,
    output logic                    ey_we,
    output logic [2*CELL_WIDTH-1:0] ex_rd_addr,
    input  wire  [DATA_WIDTH-1:0]   ex_rd_dout,
    output logic [2*CELL_WIDTH-1:0] ex_wr_addr,
    output logic [DATA_WIDTH-1:0]   ex_wr_data,
    output logic                    ex_we,
    output logic [2*CELL_WIDTH-1:0] bz_rd_addr,
    input  wire  [DATA_WIDTH-1:0]   bz_rd_dout,
    output logic [2*CELL_WIDTH-1:0] bz_wr_addr,
    output logic [DATA_WIDTH-1:0]   bz_wr_data,
    output logic                    bz_we,
    input  wire solver_enable,
    output logic solver_done,
    output logic [2*CELL_WIDTH-1:0] bz_adj_rd_addr,
    input  wire  [DATA_WIDTH-1:0]   bz_adj_dout,
    output logic [2*CELL_WIDTH-1:0] ey_adj_rd_addr,
    input  wire  [DATA_WIDTH-1:0]   ey_adj_dout,
    output logic [CELL_WIDTH-1:0]   current_row,
    output logic [CELL_WIDTH-1:0]   current_col,
    output logic                    e_phase,
    input  wire [1:0] preset,
    input  wire [3:0] slit_w,
    input  wire signed [DATA_WIDTH-1:0] cb_mat
);

    logic signed [DATA_WIDTH-1:0] engine_ey_old;
    logic signed [DATA_WIDTH-1:0] engine_ex_old;
    logic signed [DATA_WIDTH-1:0] engine_bz_right;
    logic signed [DATA_WIDTH-1:0] engine_bz_old;
    logic signed [DATA_WIDTH-1:0] engine_ey_right;
    logic signed [DATA_WIDTH-1:0] engine_ex_right;
    logic signed [DATA_WIDTH-1:0] engine_ey_left;
    wire  signed [DATA_WIDTH-1:0] engine_ey_new;
    wire  signed [DATA_WIDTH-1:0] engine_ex_new;
    wire  signed [DATA_WIDTH-1:0] engine_bz_new;
    logic signed [DATA_WIDTH-1:0] prev_bz;
    logic signed [DATA_WIDTH-1:0] prev_ey;
    logic signed [DATA_WIDTH-1:0] prev_ex;
    localparam GRID_SIZE     = ROWS * COLUMNS;
    localparam TWO_GRID_SIZE = 2 * GRID_SIZE;
    localparam ADDR_BITS     = $clog2(GRID_SIZE) + 1;
    localparam CTR_BITS      = $clog2(TWO_GRID_SIZE) + 1;

    logic [CTR_BITS-1:0]  counter;
    logic [CTR_BITS-1:0]  phase_addr;
    logic [CTR_BITS-1:0]  wr_counter;
    logic [ADDR_BITS-1:0] cell_addr;
    logic [ADDR_BITS-1:0] wr_cell;
    logic                 write_valid;
    logic                 e_write_phase;
    logic        [CELL_WIDTH-1:0] row;
    logic        [CELL_WIDTH-1:0] column;
    logic        [CELL_WIDTH-1:0] wr_row;
    logic        [CELL_WIDTH-1:0] wr_column;
    logic signed [DATA_WIDTH-1:0] engine_bz_left_ey;
    logic signed [DATA_WIDTH-1:0] engine_bz_left_ex;
    logic signed [DATA_WIDTH-1:0] ca_ey;
    logic signed [DATA_WIDTH-1:0] ca_ex;
    logic signed [DATA_WIDTH-1:0] ca_bz;
    logic signed [DATA_WIDTH-1:0] cb_ey;
    logic signed [DATA_WIDTH-1:0] cb_ex;
    logic signed [DATA_WIDTH-1:0] cb_bz;
    logic signed [DATA_WIDTH-1:0] cb_ey_m;
    logic signed [DATA_WIDTH-1:0] cb_ex_m;
    logic wall;
    logic wall_col;
    logic slit_s;
    logic slit_da;
    logic slit_db;
    logic slit_g;
    logic signed [CELL_WIDTH-1:0] d_ey;
    logic signed [CELL_WIDTH-1:0] d_ex;
    logic signed [CELL_WIDTH-1:0] d_bz;

    pml #(
        .DATA_WIDTH(DATA_WIDTH),
        .CELL_WIDTH(CELL_WIDTH),
        .PML_SIZE(PML_SIZE)
    ) pml_ey (
        .d(d_ex),
        .ca(ca_ey),
        .cb_e(cb_ey)
    );

    pml #(
        .DATA_WIDTH(DATA_WIDTH),
        .CELL_WIDTH(CELL_WIDTH),
        .PML_SIZE(PML_SIZE)
    ) pml_ex (
        .d(d_ey),
        .ca(ca_ex),
        .cb_e(cb_ex)
    );

    pml #(
        .DATA_WIDTH(DATA_WIDTH),
        .CELL_WIDTH(CELL_WIDTH),
        .PML_SIZE(PML_SIZE)
    ) pml_bz (
        .d(d_bz),
        .ca(ca_bz),
        .cb_bz(cb_bz)
    );

    assign cb_ey_m = (wr_column >= COLUMNS/2) ? cb_mat : cb_ey;
    assign cb_ex_m = (wr_column >= COLUMNS/2) ? cb_mat : cb_ex;

    fdtd_engine #(.FP_WIDTH(DATA_WIDTH)) fdtd_engine (
        .clk(clk),
        .ca_ey(ca_ey),
        .cb_ey(cb_ey_m),
        .ca_ex(ca_ex),
        .cb_ex(cb_ex_m),
        .ca_bz(ca_bz),
        .cb_bz(cb_bz),
        .ey_old(engine_ey_old),
        .ex_old(engine_ex_old),
        .bz_left_ey(engine_bz_left_ey),
        .bz_left_ex(engine_bz_left_ex),
        .bz_right(engine_bz_right),
        .bz_old(engine_bz_old),
        .ey_left(engine_ey_left),
        .ey_right(engine_ey_right),
        .ex_left(prev_ex),
        .ex_right(engine_ex_right),
        .ex_new(engine_ex_new),
        .ey_new(engine_ey_new),
        .bz_new(engine_bz_new)
    );

always_comb begin
    if (counter < GRID_SIZE) begin
        phase_addr = counter;
    end else if (counter < TWO_GRID_SIZE) begin
        phase_addr = counter - GRID_SIZE;
    end else begin
        phase_addr = '0;
    end

    cell_addr   = phase_addr;
    row         = cell_addr / COLUMNS;
    column      = cell_addr - (row * COLUMNS);
    current_row = row;
    current_col = column;
    e_phase     = (counter >= GRID_SIZE);

    wr_counter    = counter - 3'd4;
    write_valid   = (counter >= 4);
    e_write_phase = write_valid && (wr_counter < GRID_SIZE);
    if (!write_valid)       wr_cell = '0;
    else if (e_write_phase) wr_cell = wr_counter;
    else                    wr_cell = wr_counter - GRID_SIZE;
    wr_row      = (wr_cell / COLUMNS) + ROW_OFFSET;
    wr_column   = wr_cell - (wr_cell / COLUMNS) * COLUMNS;

    wall_col = (wr_column == COLUMNS/2);
    slit_s   = (wr_row >= TOTAL_ROWS/2 - slit_w) && (wr_row <= TOTAL_ROWS/2 + slit_w);
    slit_da = (wr_row >= TOTAL_ROWS/4 - slit_w) && (wr_row <= TOTAL_ROWS/4 + slit_w);
    slit_db = (wr_row >= 3*TOTAL_ROWS/4 - slit_w) && (wr_row <= 3*TOTAL_ROWS/4 + slit_w);
    slit_g  = (wr_row[2:0] < slit_w[2:0]);
    wall = 1'b0;
    case (preset)
        2'd1: wall = wall_col && !slit_s;
        2'd2: wall = wall_col && !(slit_da || slit_db);
        2'd3: wall = wall_col && !slit_g;
    endcase

    bz_adj_rd_addr    = '0;
    ey_adj_rd_addr    = '0;
    ey_rd_addr        = '0;
    ex_rd_addr        = '0;
    bz_rd_addr        = '0;
    engine_ey_left    = prev_ey;
    engine_ey_right   = ey_rd_dout;
    engine_bz_left_ey = prev_bz;
    engine_bz_left_ex = prev_bz;

    if (wr_row < PML_SIZE) d_ey = PML_SIZE - 1 - wr_row;
    else if (wr_row >= TOTAL_ROWS - PML_SIZE) d_ey = wr_row - (TOTAL_ROWS - PML_SIZE);
    else d_ey = 0;

    if (wr_column < PML_SIZE) d_ex = PML_SIZE - 1 - wr_column;
    else if (wr_column >= COLUMNS - PML_SIZE) d_ex = wr_column - (COLUMNS - PML_SIZE);
    else d_ex = 0;

    d_bz = (d_ey > d_ex) ? d_ey : d_ex;

    if (counter < GRID_SIZE) begin
        ey_rd_addr = cell_addr;
        ex_rd_addr = cell_addr;
        bz_rd_addr = cell_addr;
        if (row != 0 || !FIRST_LANE) begin
            bz_adj_rd_addr    = cell_addr - COLUMNS;
            engine_bz_left_ey = bz_adj_dout;
        end
    end else begin
        bz_rd_addr = cell_addr;
        ey_rd_addr = cell_addr;
        if (column != COLUMNS-1) begin
            ex_rd_addr = cell_addr + 1'b1;
        end
        if (row != ROWS-1 || !LAST_LANE) begin
            ey_adj_rd_addr  = cell_addr + COLUMNS;
            engine_ey_right = ey_adj_dout;
        end
        engine_ey_left = ey_rd_dout;
    end

    engine_ey_old   = ey_rd_dout;
    engine_ex_old   = ex_rd_dout;
    engine_bz_right = bz_rd_dout;
    engine_ex_right = ex_rd_dout;
    engine_bz_old   = bz_rd_dout;
end

always_ff @(posedge clk) begin
    ey_we       <= 1'b0;
    ex_we       <= 1'b0;
    bz_we       <= 1'b0;
    solver_done <= 1'b0;

    prev_bz <= bz_rd_dout;
    prev_ey <= ey_rd_dout;
    prev_ex <= ex_rd_dout;
    ey_wr_addr <= wr_cell;
    ex_wr_addr <= wr_cell;
    bz_wr_addr <= wr_cell;

    if (rst || !solver_enable) begin
        counter <= '0;
    end else begin
        if (counter == TWO_GRID_SIZE + 3) solver_done <= 1'b1;

        if (e_write_phase) begin
            ey_we <= write_valid;
            ex_we <= write_valid;
            if (wr_row == 0 || wr_row == TOTAL_ROWS-1) ey_wr_data <= '0;
            else if (source_valid && wr_cell == source_addr) ey_wr_data <= engine_ey_new + source_in;
            else ey_wr_data <= engine_ey_new;
            if (wr_column == 0 || wr_column == COLUMNS-1) ex_wr_data <= '0;
            else ex_wr_data <= engine_ex_new;
            if (wall) begin
                ey_wr_data <= '0;
                ex_wr_data <= '0;
            end
        end else begin
            bz_we      <= write_valid;
            bz_wr_data <= engine_bz_new;
        end

        if (counter < TWO_GRID_SIZE + 4) counter <= counter + 1'b1;

    end
end

endmodule
