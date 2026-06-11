// ============================================================================
//  contour_renderer_core_bd.sv
//  2D top-down contour renderer core for the BD. Drops Cyril's contour_unit
//  into our 25 MHz clk_pix datapath, replacing the D1S48 ray-march renderer
//  (ray_unit + 52 heightmap BRAMs) with contour_unit + ONE writable heightmap.
//
//    (px,py from video timing) -> contour_unit -> 1 BRAM read -> 16-band
//    diverging palette (blue troughs -> red crests) -> RGB -> HDMI.
//
//  No camera / AXI (the 2D view has none). The bridge writes the single
//  heightmap via hm_we/hm_waddr/hm_wdata during vblank; contour reads it.
// ============================================================================
module contour_renderer_core_bd (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk_pix CLK" *)
    (* X_INTERFACE_PARAMETER = "FREQ_HZ 25000000, ASSOCIATED_RESET rst_pix_n" *)
    input  wire        clk_pix,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_pix_n RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire        rst_pix_n,

    // FDTD heightmap write port (from the bridge, clk_pix domain)
    input  wire        hm_we,
    input  wire [13:0] hm_waddr,
    input  wire signed [15:0] hm_wdata,
    output wire        vblank,

    // PS-writable palette (from a GPIO, FCLK domain). pal_word carries one entry
    // {idx[27:24], rgb[23:0]}; a toggle on pal_commit latches it into palette[idx].
    input  wire [27:0] pal_word,
    input  wire        pal_commit,

    // HDMI video out (to rgb2dvi)
    output wire [23:0] vid_pData,
    output wire        vid_pVDE,
    output wire        vid_pHSync,
    output wire        vid_pVSync
);
    localparam integer W = 640, H = 480, LAT = 3;  // contour LAT = RD_LAT(1)+2

    wire [9:0] sx, sy;
    wire       hsync, vsync, active_video;

    design1_video_timing_640x480 u_timing (
        .clk_pix(clk_pix), .rst_n(rst_pix_n),
        .sx(sx), .sy(sy), .hsync(hsync), .vsync(vsync), .active_video(active_video));

    assign vblank = (sy >= H[9:0]);

    // single writable heightmap: bridge writes (port A), contour reads (port B)
    wire [13:0] c_addr;
    wire        c_re;
    wire signed [15:0] c_dout;
    heightmap_bram_rw #(.ADDR_W(14), .DATA_W(16)) u_hm (
        .clk(clk_pix), .we(hm_we), .waddr(hm_waddr), .wdata(hm_wdata),
        .addr(c_addr), .re(c_re), .dout(c_dout));

    // ---- palette write strobe: cross pal_commit (FCLK GPIO) into clk_pix and
    //      pulse pal_we for one cycle on each toggle; pal_word is stable then ----
    reg pc_s0, pc_s1, pc_s2;
    always @(posedge clk_pix) begin
        if (!rst_pix_n) begin pc_s0 <= 1'b0; pc_s1 <= 1'b0; pc_s2 <= 1'b0; end
        else            begin pc_s0 <= pal_commit; pc_s1 <= pc_s0; pc_s2 <= pc_s1; end
    end
    wire pal_we = pc_s1 ^ pc_s2;             // 1-cycle pulse per commit toggle

    wire [7:0] cr, cg, cb;
    wire       cvalid;
    contour_unit_cb #(.W(W), .H(H), .GRID_N(128), .H_W(16), .RD_LAT(1),
                      .RX(3277), .RY(4369)) u_contour (
        .clk(clk_pix), .rst_n(rst_pix_n), .en(1'b1),
        .px_in(active_video ? sx[9:0]   : 10'd0),
        .py_in(active_video ? sy[8:0]   : 9'd0),
        .valid_in(active_video),
        .bram_addr(c_addr), .bram_re(c_re), .bram_dout(c_dout),
        .pal_we(pal_we), .pal_idx(pal_word[27:24]), .pal_rgb(pal_word[23:0]),
        .r_out(cr), .g_out(cg), .b_out(cb),
        .px_out(), .py_out(), .valid_out(cvalid));

    // align hsync/vsync/DE with the contour pixel latency
    reg hs_d [0:LAT-1];
    reg vs_d [0:LAT-1];
    reg de_d [0:LAT-1];
    integer i;
    always @(posedge clk_pix) begin
        if (!rst_pix_n) begin
            for (i = 0; i < LAT; i = i + 1) begin
                hs_d[i] <= 1'b1; vs_d[i] <= 1'b1; de_d[i] <= 1'b0;
            end
        end else begin
            hs_d[0] <= hsync; vs_d[0] <= vsync; de_d[0] <= active_video;
            for (i = 1; i < LAT; i = i + 1) begin
                hs_d[i] <= hs_d[i-1]; vs_d[i] <= vs_d[i-1]; de_d[i] <= de_d[i-1];
            end
        end
    end

    assign vid_pVDE   = de_d[LAT-1] & cvalid;
    assign vid_pHSync = hs_d[LAT-1];
    assign vid_pVSync = vs_d[LAT-1];

    wire [7:0] vr = vid_pVDE ? cr : 8'd0;
    wire [7:0] vg = vid_pVDE ? cg : 8'd0;
    wire [7:0] vb = vid_pVDE ? cb : 8'd0;
    assign vid_pData = {vr, vb, vg};   // {R,B,G} order for rgb2dvi (matches D1S48)
endmodule
