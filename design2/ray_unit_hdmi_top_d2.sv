// PYNQ-Z1 HDMI wrapper for the ray renderer -- DESIGN 2 (half-rate core).
//
// Architecture change vs Design 1:
//   - The renderer core (ray_unit2) runs at 2x the pixel clock (50 MHz) and
//     produces 1 pixel every 2 core cycles  => 25 Mpix/s average.
//   - An asynchronous FIFO crosses from the 50 MHz render domain to the
//     25 MHz pixel/scanout domain.
//   - The HDMI side pops exactly one pixel per active_video cycle.
//   - The renderer is throttled by FIFO fill (valid_in gated on !almost_full)
//     so it does not overrun during blanking.
//
// Required Vivado IP:
//   - clk_wiz_0:
//       input  clk_in1  = 125 MHz PL clock
//       output clk_out1 = 25 MHz  pixel clock     (clk_pix)
//       output clk_out2 = 125 MHz serial clock    (clk_5x)
//       output clk_out3 = 50 MHz  render clock     (clk_core)   <-- NEW
//   - rgb2dvi_0: as before
//   - xpm_fifo_async (inferred via XPM macro, no IP needed)

module ray_unit_hdmi_top_d2 (
    input  logic       clk,
    input  logic       rst,

    output logic       hdmi_tx_clk_p,
    output logic       hdmi_tx_clk_n,
    output logic [2:0] hdmi_tx_p,
    output logic [2:0] hdmi_tx_n
);

    localparam int W       = 640;
    localparam int H       = 480;
    localparam int PX_W    = 10;
    localparam int PY_W    = 9;

    localparam int GRID_N  = 64;
    localparam int IDX_W   = 6;
    localparam int ADDR_W  = IDX_W * 2;

    localparam int N_STEPS = 16;
    localparam int H_W     = 16;
    localparam int DIR_W   = 16;
    localparam int POS_W   = 16;

    localparam logic signed [DIR_W-1:0] ZERO = 16'sd0;

    // Camera: close above the -X/-Y side, looking diagonally toward map centre.
    localparam logic signed [POS_W-1:0] OX = -16'sd2867;
    localparam logic signed [POS_W-1:0] OY = -16'sd2867;
    localparam logic signed [POS_W-1:0] OZ =  16'sd3686;
    localparam logic signed [DIR_W-1:0] FWD_X   =  16'sd4096;
    localparam logic signed [DIR_W-1:0] FWD_Y   =  16'sd4096;
    localparam logic signed [DIR_W-1:0] FWD_Z   = -16'sd5793;
    localparam logic signed [DIR_W-1:0] RIGHT_X =  16'sd5793;
    localparam logic signed [DIR_W-1:0] RIGHT_Y = -16'sd5793;
    localparam logic signed [DIR_W-1:0] RIGHT_Z =  16'sd0;
    localparam logic signed [DIR_W-1:0] UP_X    =  16'sd4096;
    localparam logic signed [DIR_W-1:0] UP_Y    =  16'sd4096;
    localparam logic signed [DIR_W-1:0] UP_Z    =  16'sd5793;
    loca
