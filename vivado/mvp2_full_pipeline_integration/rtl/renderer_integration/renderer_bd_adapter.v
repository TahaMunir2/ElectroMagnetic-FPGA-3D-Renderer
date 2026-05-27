`timescale 1ns/1ps

module renderer_bd_adapter #(
    parameter W = 640,
    parameter H = 480,
    parameter GRID_N = 64,
    parameter N_STEPS = 16,
    parameter H_WIDTH = 16,
    parameter ADDR_WIDTH = 12
)(
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  enable,

    input  wire                  heightmap_we,
    input  wire [ADDR_WIDTH-1:0] heightmap_waddr,
    input  wire [H_WIDTH-1:0]    heightmap_wdata,

    output wire [23:0]           rgb888,
    output wire                  valid,
    output wire                  frame_done
);

    localparam POS_WIDTH = 16;
    localparam POS_INT   = 2;
    localparam DIR_WIDTH = 16;
    localparam DIR_INT   = 2;
    localparam IDX_WIDTH = 6;
    localparam STEP_WIDTH = 5;
    localparam PX_WIDTH = 10;
    localparam PY_WIDTH = 9;

    localparam signed [POS_WIDTH-1:0] OX = 16'sd0;
    localparam signed [POS_WIDTH-1:0] OY = -16'sd8192;
    localparam signed [POS_WIDTH-1:0] OZ = 16'sd4096;
    localparam signed [DIR_WIDTH-1:0] ZERO = 16'sd0;
    localparam signed [DIR_WIDTH-1:0] ONE = 16'sd8192;
    localparam signed [DIR_WIDTH-1:0] SUN_D = 16'sd5793;

    wire rst_n;
    assign rst_n = ~rst;

    reg [PX_WIDTH-1:0] px_cnt;
    reg [PY_WIDTH-1:0] py_cnt;
    reg                valid_in;

    always @(posedge clk) begin
        if (rst) begin
            px_cnt   <= {PX_WIDTH{1'b0}};
            py_cnt   <= {PY_WIDTH{1'b0}};
            valid_in <= 1'b0;
        end else if (enable) begin
            valid_in <= 1'b1;
            if (px_cnt == W - 1) begin
                px_cnt <= {PX_WIDTH{1'b0}};
                py_cnt <= (py_cnt == H - 1) ? {PY_WIDTH{1'b0}} : py_cnt + {{(PY_WIDTH-1){1'b0}}, 1'b1};
            end else begin
                px_cnt <= px_cnt + {{(PX_WIDTH-1){1'b0}}, 1'b1};
            end
        end else begin
            valid_in <= 1'b0;
        end
    end

    wire [N_STEPS*ADDR_WIDTH-1:0] marcher_bram_addr_flat;
    wire [N_STEPS-1:0]            marcher_bram_re_flat;
    wire [N_STEPS*H_WIDTH-1:0]    marcher_bram_dout_flat;

    wire [4*ADDR_WIDTH-1:0]       normal_bram_addr_flat;
    wire [3:0]                    normal_bram_re_flat;
    wire [4*H_WIDTH-1:0]          normal_bram_dout_flat;

    wire [7:0] r_out;
    wire [7:0] g_out;
    wire [7:0] b_out;
    wire [PX_WIDTH-1:0] px_out;
    wire [PY_WIDTH-1:0] py_out;
    wire valid_out;

    genvar i;
    generate
        for (i = 0; i < N_STEPS; i = i + 1) begin : g_marcher_heightmap
            renderer_heightmap_ram #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .DATA_WIDTH(H_WIDTH)
            ) u_heightmap_ram (
                .clk(clk),
                .we(heightmap_we),
                .waddr(heightmap_waddr),
                .wdata(heightmap_wdata),
                .re(marcher_bram_re_flat[i]),
                .raddr(marcher_bram_addr_flat[i*ADDR_WIDTH +: ADDR_WIDTH]),
                .rdata(marcher_bram_dout_flat[i*H_WIDTH +: H_WIDTH])
            );
        end

        for (i = 0; i < 4; i = i + 1) begin : g_normal_heightmap
            renderer_heightmap_ram #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .DATA_WIDTH(H_WIDTH)
            ) u_heightmap_ram (
                .clk(clk),
                .we(heightmap_we),
                .waddr(heightmap_waddr),
                .wdata(heightmap_wdata),
                .re(normal_bram_re_flat[i]),
                .raddr(normal_bram_addr_flat[i*ADDR_WIDTH +: ADDR_WIDTH]),
                .rdata(normal_bram_dout_flat[i*H_WIDTH +: H_WIDTH])
            );
        end
    endgenerate

    ray_unit_synth_wrapper #(
        .W(W),
        .H(H),
        .POS_W(POS_WIDTH),
        .POS_I(POS_INT),
        .DIR_W(DIR_WIDTH),
        .DIR_I(DIR_INT),
        .GRID_N(GRID_N),
        .IDX_W(IDX_WIDTH),
        .H_W(H_WIDTH),
        .H_I(2),
        .N_STEPS(N_STEPS),
        .STEP_W(STEP_WIDTH),
        .PX_W(PX_WIDTH),
        .PY_W(PY_WIDTH)
    ) u_ray_unit (
        .clk(clk),
        .rst_n(rst_n),
        .en(enable),
        .Ox(OX),
        .Oy(OY),
        .Oz(OZ),
        .fwd_x(ZERO),
        .fwd_y(ONE),
        .fwd_z(ZERO),
        .right_x(ONE),
        .right_y(ZERO),
        .right_z(ZERO),
        .up_x(ZERO),
        .up_y(ZERO),
        .up_z(ONE),
        .sun_dx(ZERO),
        .sun_dy(SUN_D),
        .sun_dz(SUN_D),
        .px_in(px_cnt),
        .py_in(py_cnt),
        .valid_in(valid_in),
        .marcher_bram_addr_flat(marcher_bram_addr_flat),
        .marcher_bram_re_flat(marcher_bram_re_flat),
        .marcher_bram_dout_flat(marcher_bram_dout_flat),
        .normal_bram_addr_flat(normal_bram_addr_flat),
        .normal_bram_re_flat(normal_bram_re_flat),
        .normal_bram_dout_flat(normal_bram_dout_flat),
        .r_out(r_out),
        .g_out(g_out),
        .b_out(b_out),
        .px_out(px_out),
        .py_out(py_out),
        .valid_out(valid_out)
    );

    assign rgb888 = {r_out, g_out, b_out};
    assign valid = valid_out;
    assign frame_done = valid_out && (px_out == W - 1) && (py_out == H - 1);

endmodule
