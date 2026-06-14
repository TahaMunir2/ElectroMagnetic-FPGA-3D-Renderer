// ============================================================================
//  ray_unit4_f16.sv
//  ----------------------------------------------------------------------------
//  Single Design4 lane folded to one input pixel every 16 core cycles.
//  This is intended for use behind a framebuffer writer, not direct HDMI.
//
//  Per lane heightmap copies:
//      marcher16 : 12 single-port copies
//      normal4   :  2 single-port copies
//      total     : 14 copies per lane
// ============================================================================

module ray_unit4_f16 #(
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

    parameter int GRID_N      = 64,
    parameter int IDX_W       = $clog2(GRID_N),

    parameter int H_W         = 16,
    parameter int H_I         = 2,
    parameter int H_F         = H_W - 1 - H_I,

    parameter int N_STEPS     = 48,
    parameter int STEP_W      = $clog2(N_STEPS + 1),
    parameter int FRAC_W      = 8,

    parameter int PX_W        = $clog2(W),
    parameter int PY_W        = $clog2(H),

    parameter int FOLD        = 16,
    parameter int MARCH_PORTS = 12,

    parameter logic [7:0] SKY_R    = 8'd135,
    parameter logic [7:0] SKY_G    = 8'd206,
    parameter logic [7:0] SKY_B    = 8'd235,
    parameter logic [7:0] PALE_R   = 8'd192,
    parameter logic [7:0] PALE_G   = 8'd192,
    parameter logic [7:0] PALE_B   = 8'd192,
    parameter logic [7:0] AMBIENT  = 8'd64
)(
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

    output logic [IDX_W*2-1:0]         marcher_bram_addr [MARCH_PORTS],
    output logic                       marcher_bram_re   [MARCH_PORTS],
    input  logic signed [H_W-1:0]      marcher_bram_dout [MARCH_PORTS],

    output logic [IDX_W*2-1:0]         normal_bram_addr  [2],
    output logic                       normal_bram_re    [2],
    input  logic signed [H_W-1:0]      normal_bram_dout  [2],

    output logic [7:0]                 r_out,
    output logic [7:0]                 g_out,
    output logic [7:0]                 b_out,
    output logic [PX_W-1:0]            px_out,
    output logic [PY_W-1:0]            py_out,
    output logic                       valid_out,
    output logic [$clog2(FOLD)-1:0]    fold_phase
);

    logic signed [DIR_W-1:0] rg_Dx, rg_Dy, rg_Dz;
    logic [PX_W-1:0]         rg_px;
    logic [PY_W-1:0]         rg_py;
    logic                    rg_valid;

    ray_gen #(
        .W      (W),
        .H      (H),
        .DIR_W  (DIR_W),
        .DIR_I  (DIR_I),
        .UV_W   (UV_W),
        .UV_I   (UV_I),
        .K_W    (K_W),
        .K_I    (K_I),
        .K_U    (K_U),
        .K_V    (K_V)
    ) u_ray_gen (
        .clk        (clk),
        .rst_n      (rst_n),
        .px_in      (px_in),
        .py_in      (py_in),
        .valid_in   (valid_in),
        .fwd_x      (fwd_x), .fwd_y(fwd_y), .fwd_z(fwd_z),
        .right_x    (right_x), .right_y(right_y), .right_z(right_z),
        .up_x       (up_x), .up_y(up_y), .up_z(up_z),
        .stall      (1'b0),
        .Dx         (rg_Dx), .Dy(rg_Dy), .Dz(rg_Dz),
        .px_out     (rg_px),
        .py_out     (rg_py),
        .valid_out  (rg_valid)
    );

    logic [1:0]              mc_status;
    logic [IDX_W-1:0]        mc_ix_hit, mc_iy_hit;
    logic signed [H_W-1:0]   mc_h_hit;
    logic signed [POS_W-1:0] mc_Px_hit, mc_Py_hit;
    logic [STEP_W-1:0]       mc_step_count;
    logic [PX_W-1:0]         mc_px;
    logic [PY_W-1:0]         mc_py;
    logic                    mc_valid;

    marcher16 #(
        .POS_W      (POS_W),
        .POS_I      (POS_I),
        .DIR_W      (DIR_W),
        .DIR_I      (DIR_I),
        .GRID_N     (GRID_N),
        .H_W        (H_W),
        .H_I        (H_I),
        .N_STEPS    (N_STEPS),
        .FRAC_W     (FRAC_W),
        .PX_W       (PX_W),
        .PY_W       (PY_W),
        .FOLD       (FOLD),
        .BRAM_PORTS (MARCH_PORTS)
    ) u_marcher (
        .clk            (clk),
        .rst_n          (rst_n),
        .en             (en),
        .Dx_in          (rg_Dx),
        .Dy_in          (rg_Dy),
        .Dz_in          (rg_Dz),
        .px_in          (rg_px),
        .py_in          (rg_py),
        .valid_in       (rg_valid),
        .Ox             (Ox),
        .Oy             (Oy),
        .Oz             (Oz),
        .bram_addr      (marcher_bram_addr),
        .bram_re        (marcher_bram_re),
        .bram_dout      (marcher_bram_dout),
        .status_out     (mc_status),
        .ix_hit_out     (mc_ix_hit),
        .iy_hit_out     (mc_iy_hit),
        .h_hit_out      (mc_h_hit),
        .Px_hit_out     (mc_Px_hit),
        .Py_hit_out     (mc_Py_hit),
        .step_count_out (mc_step_count),
        .px_out         (mc_px),
        .py_out         (mc_py),
        .valid_out      (mc_valid),
        .phase_out      (fold_phase)
    );

    logic [1:0]              nm_status;
    logic [IDX_W-1:0]        nm_ix, nm_iy;
    logic signed [H_W-1:0]   nm_h_hit, nm_h_interp;
    logic [STEP_W-1:0]       nm_step_count;
    logic signed [DIR_W-1:0] nm_Nx, nm_Ny, nm_Nz;
    logic [PX_W-1:0]         nm_px;
    logic [PY_W-1:0]         nm_py;
    logic                    nm_valid;

    normal4 #(
        .GRID_N (GRID_N),
        .POS_W  (POS_W),
        .POS_I  (POS_I),
        .H_W    (H_W),
        .H_I    (H_I),
        .DIR_W  (DIR_W),
        .DIR_I  (DIR_I),
        .PX_W   (PX_W),
        .PY_W   (PY_W),
        .STEP_W (STEP_W)
    ) u_normal (
        .clk            (clk),
        .rst_n          (rst_n),
        .en             (en),
        .status_in      (mc_status),
        .ix_in          (mc_ix_hit),
        .iy_in          (mc_iy_hit),
        .h_hit_in       (mc_h_hit),
        .step_count_in  (mc_step_count),
        .px_in          (mc_px),
        .py_in          (mc_py),
        .valid_in       (mc_valid),
        .bram_addr      (normal_bram_addr),
        .bram_re        (normal_bram_re),
        .bram_dout      (normal_bram_dout),
        .status_out     (nm_status),
        .ix_out         (nm_ix),
        .iy_out         (nm_iy),
        .h_hit_out      (nm_h_hit),
        .h_interp_out   (nm_h_interp),
        .step_count_out (nm_step_count),
        .Nx_out         (nm_Nx),
        .Ny_out         (nm_Ny),
        .Nz_out         (nm_Nz),
        .px_out         (nm_px),
        .py_out         (nm_py),
        .valid_out      (nm_valid)
    );

    shader #(
        .H_W     (H_W),
        .H_I     (H_I),
        .DIR_W   (DIR_W),
        .DIR_I   (DIR_I),
        .N_STEPS (N_STEPS),
        .PX_W    (PX_W),
        .PY_W    (PY_W),
        .SKY_R   (SKY_R),
        .SKY_G   (SKY_G),
        .SKY_B   (SKY_B),
        .PALE_R  (PALE_R),
        .PALE_G  (PALE_G),
        .PALE_B  (PALE_B),
        .AMBIENT (AMBIENT)
    ) u_shader (
        .clk           (clk),
        .rst_n         (rst_n),
        .en            (en),
        .status_in     (nm_status),
        .h_hit_in      (nm_h_interp),
        .step_count_in (nm_step_count),
        .Nx_in         (nm_Nx),
        .Ny_in         (nm_Ny),
        .Nz_in         (nm_Nz),
        .px_in         (nm_px),
        .py_in         (nm_py),
        .valid_in      (nm_valid),
        .sun_dx        (sun_dx),
        .sun_dy        (sun_dy),
        .sun_dz        (sun_dz),
        .r_out         (r_out),
        .g_out         (g_out),
        .b_out         (b_out),
        .px_out        (px_out),
        .py_out        (py_out),
        .valid_out     (valid_out)
    );

endmodule
