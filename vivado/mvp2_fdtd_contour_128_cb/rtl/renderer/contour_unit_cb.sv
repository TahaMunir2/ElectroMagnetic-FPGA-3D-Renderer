// ============================================================================
//  contour_unit.sv  (writable-palette version)
//  ----------------------------------------------------------------------------
//  2D top-down contour renderer with a RUNTIME-WRITABLE 16-entry palette.
//
//  Compute path (one line):
//      (px,py) -> grid cell (ix,iy) -> 1 BRAM read -> band index -> palette RAM -> RGB
//
//  The palette is now a 16x24-bit memory (LUTRAM) instead of a hardcoded case.
//  It is preloaded at configuration time with DEFAULT_PAL and can be rewritten
//  one entry at a time through the {pal_we, pal_idx, pal_rgb} port. The
//  contour_palette_axil slave (or the standalone palette_loader) drives that
//  port; the PS pushes a colour-blindness-corrected palette over AXI-Lite.
//
//  Because every pixel is palette[band], rewriting these 16 entries recolours
//  the ENTIRE 640x480 image instantly - no per-pixel transform, no recompute.
//
//  Coordinate scaling: divider-free reciprocal-multiply-shift.
//  Band index: offset-binary top 4 bits of the signed height (no add/divide).
//  Latency: LAT = RD_LAT + 2 core cycles (unchanged by the palette change).
//  Throughput: 1 pixel / cycle. Single heightmap read port.
// ============================================================================

module contour_unit_cb #(
    parameter int W       = 640,
    parameter int H       = 480,

    parameter int GRID_N  = 64,
    parameter int IDX_W   = $clog2(GRID_N),
    parameter int ADDR_W  = IDX_W * 2,

    parameter int H_W     = 16,
    parameter int H_I     = 2,
    parameter int H_F     = H_W - 1 - H_I,

    parameter int PX_W    = $clog2(W),
    parameter int PY_W    = $clog2(H),

    parameter int RD_LAT  = 1,    // heightmap_bram read latency (1 or 2)

    parameter int SH      = 14,
    parameter int RX      = 1639,
    parameter int RY      = 2185
)(
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    en,

    // ----- pixel coords in -----
    input  logic [PX_W-1:0]         px_in,
    input  logic [PY_W-1:0]         py_in,
    input  logic                    valid_in,

    // ----- heightmap BRAM read port -----
    output logic [ADDR_W-1:0]       bram_addr,
    output logic                    bram_re,
    input  logic signed [H_W-1:0]   bram_dout,

    // ----- palette write port (drive from AXI-Lite slave or loader) -----
    input  logic                    pal_we,    // 1-cycle write strobe
    input  logic [3:0]              pal_idx,   // entry 0..15
    input  logic [23:0]             pal_rgb,   // {R[23:16], G[15:8], B[7:0]}

    // ----- pixel output -----
    output logic [7:0]              r_out,
    output logic [7:0]              g_out,
    output logic [7:0]              b_out,
    output logic [PX_W-1:0]         px_out,
    output logic [PY_W-1:0]         py_out,
    output logic                    valid_out
);

    localparam int CARRY = 1 + RD_LAT;
    localparam int LAT   = CARRY + 1;

    // Default palette (blue->cyan->green->yellow->orange->red). Loaded into the
    // LUTRAM at config time; overwritten at runtime by the PS-computed palette.
    localparam logic [23:0] DEFAULT_PAL [16] = '{
        24'h0000FF, 24'h0050FF, 24'h00A0FF, 24'h00FFFF,
        24'h00FFA0, 24'h00FF50, 24'h00FF00, 24'h80FF00,
        24'hC8FF00, 24'hFFFF00, 24'hFFC800, 24'hFFA000,
        24'hFF6400, 24'hFF2800, 24'hFF0000, 24'hB40000
    };

    // ---- writable palette memory (16 x 24-bit LUTRAM, async read) ----
    logic [23:0] palette [16];
    initial begin
        for (int k = 0; k < 16; k++) palette[k] = DEFAULT_PAL[k];
    end
    always_ff @(posedge clk) begin
        if (pal_we) palette[pal_idx] <= pal_rgb;  // independent of pixel `en`
    end

    // ---- combinational coordinate scaling (divider-free) + clamp ----
    logic [PX_W+16-1:0] ix_raw;
    logic [PY_W+16-1:0] iy_raw;
    logic [IDX_W-1:0]   ix_c, iy_c;

    assign ix_raw = (px_in * RX) >> SH;
    assign iy_raw = (py_in * RY) >> SH;
    assign ix_c   = (ix_raw >= GRID_N) ? IDX_W'(GRID_N-1) : ix_raw[IDX_W-1:0];
    assign iy_c   = (iy_raw >= GRID_N) ? IDX_W'(GRID_N-1) : iy_raw[IDX_W-1:0];

    // ---- address register + coordinate carry (tracks RD_LAT) ----
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

    // ---- band index -> palette lookup -> register outputs ----
    logic [3:0]  band;
    logic [23:0] rgb;

    assign band = { ~bram_dout[H_W-1], bram_dout[H_W-2 -: 3] };
    assign rgb  = palette[band];   // async LUTRAM read

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
