// ============================================================================
//  lane.sv  (one 1px/16cyc renderer lane: ray_gen -> marcher32 -> normal_fwd
//            -> shader)
//  ----------------------------------------------------------------------------
//  One lane renders one column-class of the image (the 3-lane top assigns
//  columns 3k / 3k+1 / 3k+2 to the three lanes).  marcher32 forwards the
//  hit-cell corners straight into normal_fwd, so the lane has ONLY the marcher's
//  8 shared heightmap ports (4 dual-port copies) and NO normal BRAM ports.
//
//  Latency (unchanged shape vs D4): ray_gen 4 + marcher 11*N_STEPS + normal 5
//  + shader 5.  Throughput: 1 pixel / 16 cycles.
//
//  NOTE: DT defaults to 2*WORLD_HALF/GRID_N.  With GRID_N=128 that halves the
//  per-step distance, so 32 steps reach only ~half the world.  Override DT (or
//  WORLD_HALF) to set the marching reach independently of grid resolution.
// ============================================================================

module lane #(
    parameter int W           = 640,
    parameter int H           = 480,

    parameter int POS_W       = 16,
    parameter int POS_I       = 2,
    parameter int POS_F       = POS_W - 1 - POS_I,

    parameter int DIR_W       = 16,
    parameter int DIR_I       = 2,
    parameter int DIR_F       = DIR_W - 1 - DIR_I,

    parameter int UV_W        = 16,
    parameter int UV_I        = 1,

    parameter int K_W         = 16,
    parameter int K_I         = 0,
    parameter logic signed [K_W-1:0] K_U = 16'sd137,
    parameter logic signed [K_W-1:0] K_V = 16'sd137,

    parameter int GRID_N      = 128,
    parameter int IDX_W       = $clog2(GRID_N),

    parameter int H_W         = 16,
    parameter int H_I         = 2,
    parameter int H_F         = H_W - 1 - H_I,

    parameter int N_STEPS     = 32,
    parameter int STEP_W      = $clog2(N_STEPS + 1),

    parameter int FRAC_W      = 8,
    parameter int FOLD        = 16,
    parameter int N_PORTS     = 8,

    parameter int PX_W        = $clog2(W),
    parameter int PY_W        = $clog2(H),

    parameter logic [7:0] SKY_R   = 8'd135,
    parameter logic [7:0] SKY_G   = 8'd206,
    parameter logic [7:0] SKY_B   = 8'd235,
    parameter logic [7:0] PALE_R  = 8'd192,
    parameter logic [7:0] PALE_G  = 8'd192,
    parameter logic [7:0] PALE_B  = 8'd192,
    parameter logic [7:0] AMBIENT = 8'd64,

    parameter logic signed [POS_W-1:0] WORLD_HALF = (1 <<< POS_F),
    parameter logic signed [POS_W-1:0] DT         = (2 * WORLD_HALF) / GRID_N
)(
    input  logic                       clk,
    input  logic                       rst_n,
    input  logic                       en,

    input  logic signed [POS_W-1:0]    Ox,
    input  logic signed [POS_W-1:0]    Oy,
    input  logic signed [POS_W-1:0]    Oz,
    input  logic signed [DIR_W-1:0]    fwd_x,  input logic signed [DIR_W-1:0] fwd_y,  input logic signed [DIR_W-1:0] fwd_z,
    input  logic signed [DIR_W-1:0]    right_x,input logic signed [DIR_W-1:0] right_y,input logic signed [DIR_W-1:0] right_z,
    input  logic signed [DIR_W-1:0]    up_x,   input logic signed [DIR_W-1:0] up_y,   input logic signed [DIR_W-1:0] up_z,
    input  logic signed [DIR_W-1:0]    sun_dx, input logic signed [DIR_W-1:0] sun_dy, input logic signed [DIR_W-1:0] sun_dz,

    input  logic [PX_W-1:0]            px_in,
    input  logic [PY_W-1:0]            py_in,
    input  logic                       valid_in,

    // marcher shared heightmap ports (4 dual-port copies)
    output logic [IDX_W*2-1:0]         bram_addr [N_PORTS],
    output logic                       bram_re   [N_PORTS],
    input  logic signed [H_W-1:0]      bram_dout [N_PORTS],

    output logic [7:0]                 r_out,
    output logic [7:0]                 g_out,
    output logic [7:0]                 b_out,
    output logic [PX_W-1:0]            px_out,
    output logic [PY_W-1:0]            py_out,
    output logic                       valid_out
);

    // ---------------- ray_gen ----------------
    logic signed [DIR_W-1:0] rg_Dx, rg_Dy, rg_Dz;
    logic [PX_W-1:0]         rg_px;
    logic [PY_W-1:0]         rg_py;
    logic                    rg_valid;

    ray_gen #(
        .W(W), .H(H), .DIR_W(DIR_W), .DIR_I(DIR_I),
        .UV_W(UV_W), .UV_I(UV_I), .K_W(K_W), .K_I(K_I), .K_U(K_U), .K_V(K_V)
    ) u_ray_gen (
        .clk(clk), .rst_n(rst_n),
        .px_in(px_in), .py_in(py_in), .valid_in(valid_in),
        .fwd_x(fwd_x), .fwd_y(fwd_y), .fwd_z(fwd_z),
        .right_x(right_x), .right_y(right_y), .right_z(right_z),
        .up_x(up_x), .up_y(up_y), .up_z(up_z),
        .stall(1'b0),
        .Dx(rg_Dx), .Dy(rg_Dy), .Dz(rg_Dz),
        .px_out(rg_px), .py_out(rg_py), .valid_out(rg_valid)
    );

    // ---------------- marcher32 ----------------
    logic [1:0]              mc_status;
    logic [IDX_W-1:0]        mc_ix, mc_iy;
    logic signed [H_W-1:0]   mc_hhit, mc_h00, mc_h10, mc_h01;
    logic [STEP_W-1:0]       mc_step;
    logic [PX_W-1:0]         mc_px;
    logic [PY_W-1:0]         mc_py;
    logic                    mc_valid;
    logic signed [POS_W-1:0] mc_pxh, mc_pyh;   // unused downstream

    marcher32 #(
        .POS_W(POS_W), .POS_I(POS_I), .DIR_W(DIR_W), .DIR_I(DIR_I),
        .GRID_N(GRID_N), .H_W(H_W), .H_I(H_I),
        .N_STEPS(N_STEPS), .FRAC_W(FRAC_W), .FOLD(FOLD), .N_PORTS(N_PORTS),
        .PX_W(PX_W), .PY_W(PY_W), .WORLD_HALF(WORLD_HALF), .DT(DT)
    ) u_marcher (
        .clk(clk), .rst_n(rst_n), .en(en),
        .Dx_in(rg_Dx), .Dy_in(rg_Dy), .Dz_in(rg_Dz),
        .px_in(rg_px), .py_in(rg_py), .valid_in(rg_valid),
        .Ox(Ox), .Oy(Oy), .Oz(Oz),
        .bram_addr(bram_addr), .bram_re(bram_re), .bram_dout(bram_dout),
        .status_out(mc_status), .ix_hit_out(mc_ix), .iy_hit_out(mc_iy),
        .h_hit_out(mc_hhit),
        .h00_hit_out(mc_h00), .h10_hit_out(mc_h10), .h01_hit_out(mc_h01),
        .Px_hit_out(mc_pxh), .Py_hit_out(mc_pyh),
        .step_count_out(mc_step), .px_out(mc_px), .py_out(mc_py),
        .valid_out(mc_valid)
    );

    // ---------------- normal_fwd ----------------
    logic [1:0]              nm_status;
    logic [IDX_W-1:0]        nm_ix, nm_iy;
    logic signed [H_W-1:0]   nm_hhit, nm_hint;
    logic [STEP_W-1:0]       nm_step;
    logic signed [DIR_W-1:0] nm_Nx, nm_Ny, nm_Nz;
    logic [PX_W-1:0]         nm_px;
    logic [PY_W-1:0]         nm_py;
    logic                    nm_valid;

    normal_fwd #(
        .GRID_N(GRID_N), .H_W(H_W), .H_I(H_I), .DIR_W(DIR_W), .DIR_I(DIR_I),
        .PX_W(PX_W), .PY_W(PY_W), .STEP_W(STEP_W)
    ) u_normal (
        .clk(clk), .rst_n(rst_n), .en(en),
        .status_in(mc_status), .ix_in(mc_ix), .iy_in(mc_iy),
        .h_hit_in(mc_hhit),
        .h00_in(mc_h00), .h10_in(mc_h10), .h01_in(mc_h01),
        .step_count_in(mc_step), .px_in(mc_px), .py_in(mc_py), .valid_in(mc_valid),
        .status_out(nm_status), .ix_out(nm_ix), .iy_out(nm_iy),
        .h_hit_out(nm_hhit), .h_interp_out(nm_hint), .step_count_out(nm_step),
        .Nx_out(nm_Nx), .Ny_out(nm_Ny), .Nz_out(nm_Nz),
        .px_out(nm_px), .py_out(nm_py), .valid_out(nm_valid)
    );

    // ---------------- shader ----------------
    shader #(
        .H_W(H_W), .H_I(H_I), .DIR_W(DIR_W), .DIR_I(DIR_I),
        .N_STEPS(N_STEPS), .PX_W(PX_W), .PY_W(PY_W),
        .SKY_R(SKY_R), .SKY_G(SKY_G), .SKY_B(SKY_B),
        .PALE_R(PALE_R), .PALE_G(PALE_G), .PALE_B(PALE_B), .AMBIENT(AMBIENT)
    ) u_shader (
        .clk(clk), .rst_n(rst_n), .en(en),
        .status_in(nm_status), .h_hit_in(nm_hint), .step_count_in(nm_step),
        .Nx_in(nm_Nx), .Ny_in(nm_Ny), .Nz_in(nm_Nz),
        .px_in(nm_px), .py_in(nm_py), .valid_in(nm_valid),
        .sun_dx(sun_dx), .sun_dy(sun_dy), .sun_dz(sun_dz),
        .r_out(r_out), .g_out(g_out), .b_out(b_out),
        .px_out(px_out), .py_out(py_out), .valid_out(valid_out)
    );

endmodule
