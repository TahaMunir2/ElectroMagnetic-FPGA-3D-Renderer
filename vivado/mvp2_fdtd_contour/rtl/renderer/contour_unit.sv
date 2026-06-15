// ============================================================================
//  contour_unit.sv
//  ----------------------------------------------------------------------------
//  2D top-down contour renderer. Drop-in alternative to ray_unit4 behind the
//  same pixel-streaming contract, minus all camera/lighting inputs.
//
//  Compute path (one line):
//      (px,py) -> grid cell (ix,iy) -> 1 BRAM read -> 16-band palette -> RGB
//
//  Coordinate scaling is divider-free. GRID_N/W = 64/640 = 1/10 is NOT a
//  power of two, so a reciprocal-multiply-shift is used:
//      ix = (px * RX) >> SH,  iy = (py * RY) >> SH      (then clamp to GRID_N-1)
//  with RX = round(GRID_N/W * 2^SH), RY = round(GRID_N/H * 2^SH).
//
//  Height -> band index uses an offset-binary trick (no add, no divide):
//      band = { ~height[H_W-1], height[H_W-2 -: 3] }    // top 4 bits, unsigned
//  16 hard-edged bands -> the banding IS the contour look.
//
//  Latency: LAT = RD_LAT + 2 core cycles (address reg + BRAM read + output reg).
//  Set RD_LAT to your heightmap_bram's true read latency:
//      RD_LAT = 1  -> simple "dout <= mem[addr]" BRAM      (LAT = 3)
//      RD_LAT = 2  -> BRAM with an extra output register   (LAT = 4)
//  The coordinate-carry pipeline auto-tracks RD_LAT so the image never shifts.
//
//  Throughput: 1 pixel / cycle. Single BRAM read port.
// ============================================================================

module contour_unit #(
    parameter int W       = 640,
    parameter int H       = 480,

    parameter int GRID_N  = 64,
    parameter int IDX_W   = $clog2(GRID_N),
    parameter int ADDR_W  = IDX_W * 2,

    parameter int H_W     = 16,   // signed Q(H_I).(H_F) height word
    parameter int H_I     = 2,
    parameter int H_F     = H_W - 1 - H_I,

    parameter int PX_W    = $clog2(W),
    parameter int PY_W    = $clog2(H),

    parameter int RD_LAT  = 1,    // heightmap_bram read latency (cycles)

    // reciprocal-multiply-shift constants
    parameter int SH      = 14,
    parameter int RX      = 1639, // round(64/640 * 2^14) = 1638.4 -> 1639
    parameter int RY      = 2185  // round(64/480 * 2^14) = 2184.5 -> 2185
)(
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    en,

    input  logic [PX_W-1:0]         px_in,
    input  logic [PY_W-1:0]         py_in,
    input  logic                    valid_in,

    output logic [ADDR_W-1:0]       bram_addr,
    output logic                    bram_re,
    input  logic signed [H_W-1:0]   bram_dout,

    output logic [7:0]              r_out,
    output logic [7:0]              g_out,
    output logic [7:0]              b_out,
    output logic [PX_W-1:0]         px_out,
    output logic [PY_W-1:0]         py_out,
    output logic                    valid_out
);

    localparam int CARRY = 1 + RD_LAT;  // coord carry stages before output reg
    localparam int LAT   = CARRY + 1;   // total latency to valid_out

    // ---- combinational coordinate scaling (divider-free) + clamp ----
    logic [PX_W+16-1:0] ix_raw;
    logic [PY_W+16-1:0] iy_raw;
    logic [IDX_W-1:0]   ix_c, iy_c;

    assign ix_raw = (px_in * RX) >> SH;
    assign iy_raw = (py_in * RY) >> SH;
    assign ix_c   = (ix_raw >= GRID_N) ? IDX_W'(GRID_N-1) : ix_raw[IDX_W-1:0];
    assign iy_c   = (iy_raw >= GRID_N) ? IDX_W'(GRID_N-1) : iy_raw[IDX_W-1:0];

    // ---- address register (1 stage) + coordinate carry (CARRY stages) ----
    logic [IDX_W-1:0] ix_s1, iy_s1;
    logic [PX_W-1:0]  px_c [CARRY];
    logic [PY_W-1:0]  py_c [CARRY];
    logic             v_c  [CARRY];

    integer i;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            ix_s1 <= '0; iy_s1 <= '0;
            for (i = 0; i < CARRY; i++) begin
                px_c[i] <= '0; py_c[i] <= '0; v_c[i] <= 1'b0;
            end
        end else if (en) begin
            ix_s1   <= ix_c;  iy_s1 <= iy_c;
            px_c[0] <= px_in; py_c[0] <= py_in; v_c[0] <= valid_in;
            for (i = 1; i < CARRY; i++) begin
                px_c[i] <= px_c[i-1];
                py_c[i] <= py_c[i-1];
                v_c[i]  <= v_c[i-1];
            end
        end
    end

    assign bram_addr = {iy_s1, ix_s1};
    assign bram_re   = 1'b1;

    // ---- height -> band -> palette ; register outputs ----
    logic [3:0]  band;
    logic [23:0] rgb;

    assign band = { ~bram_dout[H_W-1], bram_dout[H_W-2 -: 3] };

    always_comb begin
        case (band)
            4'd0 : rgb = {8'd0,   8'd0,   8'd255};
            4'd1 : rgb = {8'd0,   8'd80,  8'd255};
            4'd2 : rgb = {8'd0,   8'd160, 8'd255};
            4'd3 : rgb = {8'd0,   8'd255, 8'd255};
            4'd4 : rgb = {8'd0,   8'd255, 8'd160};
            4'd5 : rgb = {8'd0,   8'd255, 8'd80};
            4'd6 : rgb = {8'd0,   8'd255, 8'd0};
            4'd7 : rgb = {8'd128, 8'd255, 8'd0};
            4'd8 : rgb = {8'd200, 8'd255, 8'd0};
            4'd9 : rgb = {8'd255, 8'd255, 8'd0};
            4'd10: rgb = {8'd255, 8'd200, 8'd0};
            4'd11: rgb = {8'd255, 8'd160, 8'd0};
            4'd12: rgb = {8'd255, 8'd100, 8'd0};
            4'd13: rgb = {8'd255, 8'd40,  8'd0};
            4'd14: rgb = {8'd255, 8'd0,   8'd0};
            4'd15: rgb = {8'd180, 8'd0,   8'd0};
        endcase
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            r_out <= 8'd0; g_out <= 8'd0; b_out <= 8'd0;
            px_out <= '0; py_out <= '0; valid_out <= 1'b0;
        end else if (en) begin
            r_out     <= rgb[23:16];
            g_out     <= rgb[15:8];
            b_out     <= rgb[7:0];
            px_out    <= px_c[CARRY-1];
            py_out    <= py_c[CARRY-1];
            valid_out <= v_c[CARRY-1];
        end
    end

endmodule
