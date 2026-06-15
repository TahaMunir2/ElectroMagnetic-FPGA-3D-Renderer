// ============================================================================
//  d4s48_renderer_core_bd.v
//  Thin Verilog top for the BD module-reference (the BD requires a Verilog top;
//  the implementation in d4s48_core_impl.sv is SystemVerilog). Carries the
//  X_INTERFACE attributes so the block design infers the clock/reset interfaces.
// ============================================================================
module d4s48_renderer_core_bd (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk_pix CLK" *)
    (* X_INTERFACE_PARAMETER = "FREQ_HZ 25000000, ASSOCIATED_RESET rst_pix_n" *)
    input  wire        clk_pix,
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk_core CLK" *)
    (* X_INTERFACE_PARAMETER = "FREQ_HZ 100000000" *)
    input  wire        clk_core,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_pix_n RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire        rst_pix_n,

    input  wire        hm_we,
    input  wire [11:0] hm_waddr,
    input  wire signed [15:0] hm_wdata,
    output wire        vblank,

    // Runtime camera basis (PS-loaded; defaults to fixed isometric until cam_load)
    input  wire signed [15:0] cam_ox,
    input  wire signed [15:0] cam_oy,
    input  wire signed [15:0] cam_oz,
    input  wire signed [15:0] cam_fwd_x,
    input  wire signed [15:0] cam_fwd_y,
    input  wire signed [15:0] cam_fwd_z,
    input  wire signed [15:0] cam_right_x,
    input  wire signed [15:0] cam_right_y,
    input  wire signed [15:0] cam_right_z,
    input  wire signed [15:0] cam_up_x,
    input  wire signed [15:0] cam_up_y,
    input  wire signed [15:0] cam_up_z,
    input  wire        cam_load,

    output wire [23:0] vid_pData,
    output wire        vid_pVDE,
    output wire        vid_pHSync,
    output wire        vid_pVSync
);
    d4s48_core_impl u_impl (
        .clk_pix(clk_pix), .clk_core(clk_core), .rst_pix_n(rst_pix_n),
        .hm_we(hm_we), .hm_waddr(hm_waddr), .hm_wdata(hm_wdata), .vblank(vblank),
        .cam_ox(cam_ox), .cam_oy(cam_oy), .cam_oz(cam_oz),
        .cam_fwd_x(cam_fwd_x), .cam_fwd_y(cam_fwd_y), .cam_fwd_z(cam_fwd_z),
        .cam_right_x(cam_right_x), .cam_right_y(cam_right_y), .cam_right_z(cam_right_z),
        .cam_up_x(cam_up_x), .cam_up_y(cam_up_y), .cam_up_z(cam_up_z),
        .cam_load(cam_load),
        .vid_pData(vid_pData), .vid_pVDE(vid_pVDE),
        .vid_pHSync(vid_pHSync), .vid_pVSync(vid_pVSync)
    );
endmodule
