`timescale 1ns/1ps

module fdtd_solver_bd_adapter #(
    parameter CELLS = 192,
    parameter CELL_WIDTH = 8,
    parameter DATA_WIDTH = 16,
    parameter [2*CELL_WIDTH-1:0] SOURCE_ADDR = 16'd18528
)(
    input  wire clk,
    input  wire rst,
    input  wire solver_enable,

    input  wire [DATA_WIDTH-1:0] source_q313,
    input  wire                  source_valid,
    output wire                  source_latched,
    output wire [31:0]           solver_checksum,
    output wire                  solver_done,

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

    localparam signed [DATA_WIDTH-1:0] C_E_Q313 = 16'sd717;
    localparam signed [DATA_WIDTH-1:0] C_B_Q313 = 16'sd2867;

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

    assign solver_write_event = ey_we | ex_we | bz_we;
    assign solver_write_mix =
        (ey_we ? ({ey_wr_addr, ey_wr_data} ^ 32'h45590000) : 32'd0) ^
        (ex_we ? ({ex_wr_addr, ex_wr_data} ^ 32'h45580000) : 32'd0) ^
        (bz_we ? ({bz_wr_addr, bz_wr_data} ^ 32'h425a0000) : 32'd0);

    fdtd_solver #(
        .CELLS(CELLS),
        .CELL_WIDTH(CELL_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_solver (
        .clk(clk),
        .rst(rst),
        .C_E(C_E_Q313),
        .C_B(C_B_Q313),
        .source_in(held_source_q313),
        .source_valid(held_source_valid),
        .source_addr(SOURCE_ADDR),
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
        .solver_enable(solver_enable),
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
