`timescale 1ns/1ps

module fdtd_solver_bd_adapter #(
    parameter CELLS      = 64,
    parameter CELL_WIDTH = 6,
    parameter DATA_WIDTH = 16,
    parameter PML_SIZE   = 6
)(
    input  wire clk,
    input  wire rst,
    input  wire solver_enable,

    // Free-run mode: when high, the solver auto-restarts a new iteration after
    // the field-magnitude scan completes (frame_done).  The solver is held off
    // during the scan so the magnitude unit reads stable field BRAMs.
    // When free_run is low, solver_enable passes straight through (manual mode,
    // identical to the original ping-pong design).
    input  wire free_run,
    input  wire frame_done,          // = field_magnitude done pulse (mag_done)

    input  wire [DATA_WIDTH-1:0]     source_q313,
    input  wire                      source_valid,
    output wire                      source_latched,
    output wire [31:0]               solver_checksum,
    output wire                      solver_done,

    // Runtime source injection address (centre of grid = CELLS/2 * CELLS + CELLS/2)
    input  wire [2*CELL_WIDTH-1:0]   source_addr,
    // Up to 4 coherent sources for interference; per-source enable {3,2,1,0}.
    input  wire [2*CELL_WIDTH-1:0]   source_addr1,
    input  wire [2*CELL_WIDTH-1:0]   source_addr2,
    input  wire [2*CELL_WIDTH-1:0]   source_addr3,
    input  wire [3:0]                source_en,

    output wire [2*CELL_WIDTH-1:0] ey_addra,
    output wire                    ey_ena,
    output wire [0:0]              ey_wea,
    output wire [DATA_WIDTH-1:0]   ey_dina,
    input  wire [DATA_WIDTH-1:0]   ey_douta,
    output wire [2*CELL_WIDTH-1:0] ey_addrb,
    output wire                    ey_enb,
    output wire [0:0]              ey_web,
    output wire [DATA_WIDTH-1:0]   ey_dinb,
    input  wire [DATA_WIDTH-1:0]   ey_doutb,

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
    input  wire [DATA_WIDTH-1:0]   bz_doutb
);

    reg [DATA_WIDTH-1:0] held_source_q313;
    reg                  held_source_valid;
    reg [31:0]           checksum_reg;

    wire [2*CELL_WIDTH-1:0] ey_rd_addr;
    wire [2*CELL_WIDTH-1:0] ey_wr_addr;
    wire [DATA_WIDTH-1:0]   ey_wr_data;
    wire                    ey_we;
    wire [2*CELL_WIDTH-1:0] ey_adj_rd_addr;

    wire [2*CELL_WIDTH-1:0] ex_rd_addr;
    wire [2*CELL_WIDTH-1:0] ex_wr_addr;
    wire [DATA_WIDTH-1:0]   ex_wr_data;
    wire                    ex_we;

    wire [2*CELL_WIDTH-1:0] bz_rd_addr;
    wire [2*CELL_WIDTH-1:0] bz_wr_addr;
    wire [DATA_WIDTH-1:0]   bz_wr_data;
    wire                    bz_we;
    wire [2*CELL_WIDTH-1:0] bz_adj_rd_addr;
    wire                    solver_write_event;
    wire [31:0]             solver_write_mix;

    always @(posedge clk) begin
        if (rst) begin
            held_source_q313  <= {DATA_WIDTH{1'b0}};
            held_source_valid <= 1'b0;
            checksum_reg      <= 32'd0;
        end else begin
            if (source_valid) begin
                held_source_q313  <= source_q313;
                held_source_valid <= 1'b1;
            end
            if (solver_write_event) begin
                checksum_reg <= {checksum_reg[30:0], checksum_reg[31]} ^ solver_write_mix;
            end
        end
    end

    assign source_latched = held_source_valid;
    assign solver_checksum = checksum_reg;

    // ------------------------------------------------------------------
    //  Free-run control FSM
    //
    //  S_SOLVE   : solver runs one full iteration (counter 0..2*GRID-1).
    //  S_WAITMAG : solver_done seen; hold solver off (counter resets to 0)
    //              while field_magnitude scans the shared Ey/Ex/Bz BRAMs.
    //              On frame_done (mag_done) restart -> S_SOLVE.
    //
    //  fsm_run drives the core only when free_run=1; otherwise the external
    //  solver_enable passes straight through (proven manual behaviour).
    // ------------------------------------------------------------------
    localparam S_SOLVE = 1'b0, S_WAITMAG = 1'b1;
    reg  fr_state;
    wire solver_enable_core;

    always @(posedge clk) begin
        if (rst) begin
            fr_state <= S_SOLVE;        // begin solving as soon as reset clears
        end else begin
            case (fr_state)
                S_SOLVE:   if (solver_done) fr_state <= S_WAITMAG;
                S_WAITMAG: if (frame_done)  fr_state <= S_SOLVE;
            endcase
        end
    end

    assign solver_enable_core = free_run ? (fr_state == S_SOLVE) : solver_enable;

    assign solver_write_event = ey_we | ex_we | bz_we;
    assign solver_write_mix =
        (ey_we ? ({ey_wr_addr, ey_wr_data} ^ 32'h45590000) : 32'd0) ^
        (ex_we ? ({ex_wr_addr, ex_wr_data} ^ 32'h45580000) : 32'd0) ^
        (bz_we ? ({bz_wr_addr, bz_wr_data} ^ 32'h425a0000) : 32'd0);

    fdtd_solver #(
        .CELLS(CELLS),
        .CELL_WIDTH(CELL_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .PML_SIZE(PML_SIZE)
    ) u_solver (
        .clk(clk),
        .rst(rst),
        .source_in(held_source_q313),
        .source_valid(held_source_valid),
        .source_addr(source_addr),
        .source_addr1(source_addr1),
        .source_addr2(source_addr2),
        .source_addr3(source_addr3),
        .source_en(source_en),
        .ey_rd_addr(ey_rd_addr),
        .ey_rd_dout(ey_douta),
        .ey_wr_addr(ey_wr_addr),
        .ey_wr_data(ey_wr_data),
        .ey_we(ey_we),
        .ex_rd_addr(ex_rd_addr),
        .ex_rd_dout(ex_douta),
        .ex_wr_addr(ex_wr_addr),
        .ex_wr_data(ex_wr_data),
        .ex_we(ex_we),
        .bz_rd_addr(bz_rd_addr),
        .bz_rd_dout(bz_douta),
        .bz_wr_addr(bz_wr_addr),
        .bz_wr_data(bz_wr_data),
        .bz_we(bz_we),
        .solver_enable(solver_enable_core),
        .solver_done(solver_done),
        .bz_adj_rd_addr(bz_adj_rd_addr),
        .bz_adj_dout(bz_doutb),
        .ey_adj_rd_addr(ey_adj_rd_addr),
        .ey_adj_dout(ey_doutb)
    );

    assign ey_addra = ey_rd_addr;
    assign ey_ena   = 1'b1;
    assign ey_wea   = 1'b0;
    assign ey_dina  = {DATA_WIDTH{1'b0}};
    assign ey_addrb = ey_we ? ey_wr_addr : ey_adj_rd_addr;
    assign ey_enb   = 1'b1;
    assign ey_web   = ey_we;
    assign ey_dinb  = ey_wr_data;

    assign ex_addra = ex_rd_addr;
    assign ex_ena   = 1'b1;
    assign ex_wea   = 1'b0;
    assign ex_dina  = {DATA_WIDTH{1'b0}};
    assign ex_addrb = ex_wr_addr;
    assign ex_enb   = 1'b1;
    assign ex_web   = ex_we;
    assign ex_dinb  = ex_wr_data;

    assign bz_addra = bz_rd_addr;
    assign bz_ena   = 1'b1;
    assign bz_wea   = 1'b0;
    assign bz_dina  = {DATA_WIDTH{1'b0}};
    assign bz_addrb = bz_we ? bz_wr_addr : bz_adj_rd_addr;
    assign bz_enb   = 1'b1;
    assign bz_web   = bz_we;
    assign bz_dinb  = bz_wr_data;

endmodule
