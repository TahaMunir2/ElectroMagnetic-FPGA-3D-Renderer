// Verilog shim for Vivado block-design module reference.
// The implementation is SystemVerilog in D4L3F16/ray_unit4_lanes3_f16_axis.sv.

module ray_unit4_lanes3_f16_axis_bd (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    (* X_INTERFACE_PARAMETER = "FREQ_HZ 100000000, ASSOCIATED_BUSIF M_AXIS, ASSOCIATED_RESET rst_n" *)
    input wire clk,

    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_n RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input wire rst_n,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TDATA" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M_AXIS, TDATA_NUM_BYTES 3, HAS_TKEEP 1, HAS_TLAST 1, HAS_TREADY 1, TUSER_WIDTH 1, FREQ_HZ 100000000" *)
    output wire [23:0] m_axis_tdata,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TVALID" *)
    output wire m_axis_tvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TREADY" *)
    input wire m_axis_tready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TUSER" *)
    output wire m_axis_tuser,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TLAST" *)
    output wire m_axis_tlast,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TKEEP" *)
    output wire [2:0] m_axis_tkeep,

    output wire frame_start_pulse,
    output wire frame_done_pulse,
    output wire reorder_overflow
);

    localparam signed [15:0] OX = -16'sd2867;
    localparam signed [15:0] OY = -16'sd2867;
    localparam signed [15:0] OZ =  16'sd3686;
    localparam signed [15:0] FWD_X   =  16'sd4096;
    localparam signed [15:0] FWD_Y   =  16'sd4096;
    localparam signed [15:0] FWD_Z   = -16'sd5793;
    localparam signed [15:0] RIGHT_X =  16'sd5793;
    localparam signed [15:0] RIGHT_Y = -16'sd5793;
    localparam signed [15:0] RIGHT_Z =  16'sd0;
    localparam signed [15:0] UP_X    =  16'sd4096;
    localparam signed [15:0] UP_Y    =  16'sd4096;
    localparam signed [15:0] UP_Z    =  16'sd5793;
    localparam signed [15:0] SUN_D   =  16'sd5793;
    localparam signed [15:0] ZERO    =  16'sd0;

    wire [9:0] axis_x_unused;
    wire [8:0] axis_y_unused;

    assign m_axis_tkeep = 3'b111;

    ray_unit4_lanes3_f16_axis #(
        .W(640),
        .H(480),
        .GRID_N(64),
        .N_STEPS(48)
    ) u_renderer (
        .clk(clk),
        .rst_n(rst_n),
        .Ox(OX), .Oy(OY), .Oz(OZ),
        .fwd_x(FWD_X), .fwd_y(FWD_Y), .fwd_z(FWD_Z),
        .right_x(RIGHT_X), .right_y(RIGHT_Y), .right_z(RIGHT_Z),
        .up_x(UP_X), .up_y(UP_Y), .up_z(UP_Z),
        .sun_dx(ZERO), .sun_dy(SUN_D), .sun_dz(SUN_D),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tuser(m_axis_tuser),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_x(axis_x_unused),
        .m_axis_y(axis_y_unused),
        .frame_start_pulse(frame_start_pulse),
        .frame_done_pulse(frame_done_pulse),
        .reorder_overflow(reorder_overflow)
    );

endmodule
