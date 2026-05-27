`timescale 1ns/1ps

module ray_unit_synth_wrapper #(
    parameter int W       = 640,
    parameter int H       = 480,
    parameter int POS_W   = 16,
    parameter int POS_I   = 2,
    parameter int DIR_W   = 16,
    parameter int DIR_I   = 2,
    parameter int GRID_N  = 64,
    parameter int IDX_W   = $clog2(GRID_N),
    parameter int H_W     = 16,
    parameter int H_I     = 2,
    parameter int N_STEPS = 16,
    parameter int STEP_W  = $clog2(N_STEPS + 1),
    parameter int PX_W    = $clog2(W),
    parameter int PY_W    = $clog2(H)
) (
    input  logic                       clk,
    input  logic                       rst_n,
    input  logic                       en,

    input  logic signed [POS_W-1:0]    Ox,
    input  logic signed [POS_W-1:0]    Oy,
    input  logic signed [POS_W-1:0]    Oz,
    input  logic signed [DIR_W-1:0]    fwd_x,
    input  logic signed [DIR_W-1:0]    fwd_y,
    input  logic signed [DIR_W-1:0]    fwd_z,
    input  logic signed [DIR_W-1:0]    right_x,
    input  logic signed [DIR_W-1:0]    right_y,
    input  logic signed [DIR_W-1:0]    right_z,
    input  logic signed [DIR_W-1:0]    up_x,
    input  logic signed [DIR_W-1:0]    up_y,
    input  logic signed [DIR_W-1:0]    up_z,
    input  logic signed [DIR_W-1:0]    sun_dx,
    input  logic signed [DIR_W-1:0]    sun_dy,
    input  logic signed [DIR_W-1:0]    sun_dz,

    input  logic [PX_W-1:0]            px_in,
    input  logic [PY_W-1:0]            py_in,
    input  logic                       valid_in,

    output logic [N_STEPS*IDX_W*2-1:0] marcher_bram_addr_flat,
    output logic [N_STEPS-1:0]         marcher_bram_re_flat,
    input  logic [N_STEPS*H_W-1:0]     marcher_bram_dout_flat,

    output logic [4*IDX_W*2-1:0]       normal_bram_addr_flat,
    output logic [3:0]                 normal_bram_re_flat,
    input  logic [4*H_W-1:0]           normal_bram_dout_flat,

    output logic [7:0]                 r_out,
    output logic [7:0]                 g_out,
    output logic [7:0]                 b_out,
    output logic [PX_W-1:0]            px_out,
    output logic [PY_W-1:0]            py_out,
    output logic                       valid_out
);

    logic [IDX_W*2-1:0]    marcher_bram_addr [N_STEPS];
    logic                  marcher_bram_re   [N_STEPS];
    logic signed [H_W-1:0] marcher_bram_dout [N_STEPS];
    logic [IDX_W*2-1:0]    normal_bram_addr  [4];
    logic                  normal_bram_re    [4];
    logic signed [H_W-1:0] normal_bram_dout  [4];

    genvar i;
    generate
        for (i = 0; i < N_STEPS; i = i + 1) begin : g_marcher_flatten
            assign marcher_bram_addr_flat[i*IDX_W*2 +: IDX_W*2] = marcher_bram_addr[i];
            assign marcher_bram_re_flat[i] = marcher_bram_re[i];
            assign marcher_bram_dout[i] = $signed(marcher_bram_dout_flat[i*H_W +: H_W]);
        end

        for (i = 0; i < 4; i = i + 1) begin : g_normal_flatten
            assign normal_bram_addr_flat[i*IDX_W*2 +: IDX_W*2] = normal_bram_addr[i];
            assign normal_bram_re_flat[i] = normal_bram_re[i];
            assign normal_bram_dout[i] = $signed(normal_bram_dout_flat[i*H_W +: H_W]);
        end
    endgenerate

    ray_unit #(
        .W(W),
        .H(H),
        .POS_W(POS_W),
        .POS_I(POS_I),
        .DIR_W(DIR_W),
        .DIR_I(DIR_I),
        .GRID_N(GRID_N),
        .IDX_W(IDX_W),
        .H_W(H_W),
        .H_I(H_I),
        .N_STEPS(N_STEPS),
        .STEP_W(STEP_W),
        .PX_W(PX_W),
        .PY_W(PY_W)
    ) u_ray_unit (
        .clk(clk),
        .rst_n(rst_n),
        .en(en),
        .Ox(Ox),
        .Oy(Oy),
        .Oz(Oz),
        .fwd_x(fwd_x),
        .fwd_y(fwd_y),
        .fwd_z(fwd_z),
        .right_x(right_x),
        .right_y(right_y),
        .right_z(right_z),
        .up_x(up_x),
        .up_y(up_y),
        .up_z(up_z),
        .sun_dx(sun_dx),
        .sun_dy(sun_dy),
        .sun_dz(sun_dz),
        .px_in(px_in),
        .py_in(py_in),
        .valid_in(valid_in),
        .marcher_bram_addr(marcher_bram_addr),
        .marcher_bram_re(marcher_bram_re),
        .marcher_bram_dout(marcher_bram_dout),
        .normal_bram_addr(normal_bram_addr),
        .normal_bram_re(normal_bram_re),
        .normal_bram_dout(normal_bram_dout),
        .r_out(r_out),
        .g_out(g_out),
        .b_out(b_out),
        .px_out(px_out),
        .py_out(py_out),
        .valid_out(valid_out)
    );

endmodule
