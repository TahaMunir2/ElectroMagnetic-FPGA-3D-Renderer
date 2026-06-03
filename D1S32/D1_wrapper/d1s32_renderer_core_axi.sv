// AXI-controlled D1S32 ray renderer core.
// clk_wiz, rgb2dvi, and the Zynq PS live in the Vivado block design.

module d1s32_renderer_core_axi (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk_pix CLK" *)
    (* X_INTERFACE_PARAMETER = "FREQ_HZ 25000000, ASSOCIATED_RESET rst_pix_n" *)
    input  logic        clk_pix,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_pix_n RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  logic        rst_pix_n,

    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 s_axi_aclk CLK" *)
    (* X_INTERFACE_PARAMETER = "FREQ_HZ 50000000, ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET s_axi_aresetn" *)
    input  logic        s_axi_aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 s_axi_aresetn RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  logic        s_axi_aresetn,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR" *)
    input  logic [6:0]  s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWPROT" *)
    input  logic [2:0]  s_axi_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
    input  logic        s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
    output logic        s_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
    input  logic [31:0] s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
    input  logic [3:0]  s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
    input  logic        s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
    output logic        s_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
    output logic [1:0]  s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
    output logic        s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
    input  logic        s_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
    input  logic [6:0]  s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *)
    input  logic [2:0]  s_axi_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
    input  logic        s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
    output logic        s_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
    output logic [31:0] s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
    output logic [1:0]  s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
    output logic        s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
    input  logic        s_axi_rready,

    output logic [23:0] vid_pData,
    output logic        vid_pVDE,
    output logic        vid_pHSync,
    output logic        vid_pVSync
);

    localparam int W              = 640;
    localparam int H              = 480;
    localparam int PX_W           = 10;
    localparam int PY_W           = 9;
    localparam int RENDER_LATENCY = 142;

    localparam int GRID_N  = 64;
    localparam int IDX_W   = 6;
    localparam int ADDR_W  = IDX_W * 2;

    localparam int N_STEPS = 32;
    localparam int H_W     = 16;
    localparam int DIR_W   = 16;
    localparam int POS_W   = 16;

    localparam logic signed [DIR_W-1:0] ZERO = 16'sd0;

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
    localparam logic signed [DIR_W-1:0] SUN_D   =  16'sd5793;

    logic signed [15:0] shadow_Ox;
    logic signed [15:0] shadow_Oy;
    logic signed [15:0] shadow_Oz;
    logic signed [15:0] shadow_fwd_x;
    logic signed [15:0] shadow_fwd_y;
    logic signed [15:0] shadow_fwd_z;
    logic signed [15:0] shadow_right_x;
    logic signed [15:0] shadow_right_y;
    logic signed [15:0] shadow_right_z;
    logic signed [15:0] shadow_up_x;
    logic signed [15:0] shadow_up_y;
    logic signed [15:0] shadow_up_z;
    logic               commit_req_toggle_axi;
    logic               commit_ack_toggle_pix;

    camera_ctrl_axi u_camera_ctrl (
        .s_axi_aclk        (s_axi_aclk),
        .s_axi_aresetn     (s_axi_aresetn),
        .s_axi_awaddr      (s_axi_awaddr),
        .s_axi_awprot      (s_axi_awprot),
        .s_axi_awvalid     (s_axi_awvalid),
        .s_axi_awready     (s_axi_awready),
        .s_axi_wdata       (s_axi_wdata),
        .s_axi_wstrb       (s_axi_wstrb),
        .s_axi_wvalid      (s_axi_wvalid),
        .s_axi_wready      (s_axi_wready),
        .s_axi_bresp       (s_axi_bresp),
        .s_axi_bvalid      (s_axi_bvalid),
        .s_axi_bready      (s_axi_bready),
        .s_axi_araddr      (s_axi_araddr),
        .s_axi_arprot      (s_axi_arprot),
        .s_axi_arvalid     (s_axi_arvalid),
        .s_axi_arready     (s_axi_arready),
        .s_axi_rdata       (s_axi_rdata),
        .s_axi_rresp       (s_axi_rresp),
        .s_axi_rvalid      (s_axi_rvalid),
        .s_axi_rready      (s_axi_rready),
        .commit_ack_toggle (commit_ack_toggle_pix),
        .commit_req_toggle (commit_req_toggle_axi),
        .shadow_Ox         (shadow_Ox),
        .shadow_Oy         (shadow_Oy),
        .shadow_Oz         (shadow_Oz),
        .shadow_fwd_x      (shadow_fwd_x),
        .shadow_fwd_y      (shadow_fwd_y),
        .shadow_fwd_z      (shadow_fwd_z),
        .shadow_right_x    (shadow_right_x),
        .shadow_right_y    (shadow_right_y),
        .shadow_right_z    (shadow_right_z),
        .shadow_up_x       (shadow_up_x),
        .shadow_up_y       (shadow_up_y),
        .shadow_up_z       (shadow_up_z)
    );

    logic [9:0] sx;
    logic [9:0] sy;
    logic       hsync;
    logic       vsync;
    logic       active_video;
    logic       frame_start;

    assign frame_start = (sx == 10'd0) && (sy == 10'd0);

    design1_video_timing_640x480 u_timing (
        .clk_pix      (clk_pix),
        .rst_n        (rst_pix_n),
        .sx           (sx),
        .sy           (sy),
        .hsync        (hsync),
        .vsync        (vsync),
        .active_video (active_video)
    );

    (* ASYNC_REG = "TRUE" *) logic commit_req_meta;
    (* ASYNC_REG = "TRUE" *) logic commit_req_sync;
    logic commit_req_seen;

    logic signed [POS_W-1:0] live_Ox;
    logic signed [POS_W-1:0] live_Oy;
    logic signed [POS_W-1:0] live_Oz;
    logic signed [DIR_W-1:0] live_fwd_x;
    logic signed [DIR_W-1:0] live_fwd_y;
    logic signed [DIR_W-1:0] live_fwd_z;
    logic signed [DIR_W-1:0] live_right_x;
    logic signed [DIR_W-1:0] live_right_y;
    logic signed [DIR_W-1:0] live_right_z;
    logic signed [DIR_W-1:0] live_up_x;
    logic signed [DIR_W-1:0] live_up_y;
    logic signed [DIR_W-1:0] live_up_z;

    always_ff @(posedge clk_pix) begin
        if (!rst_pix_n) begin
            commit_req_meta       <= 1'b0;
            commit_req_sync       <= 1'b0;
            commit_req_seen       <= 1'b0;
            commit_ack_toggle_pix <= 1'b0;

            live_Ox      <= OX;
            live_Oy      <= OY;
            live_Oz      <= OZ;
            live_fwd_x   <= FWD_X;
            live_fwd_y   <= FWD_Y;
            live_fwd_z   <= FWD_Z;
            live_right_x <= RIGHT_X;
            live_right_y <= RIGHT_Y;
            live_right_z <= RIGHT_Z;
            live_up_x    <= UP_X;
            live_up_y    <= UP_Y;
            live_up_z    <= UP_Z;
        end else begin
            commit_req_meta <= commit_req_toggle_axi;
            commit_req_sync <= commit_req_meta;

            if ((commit_req_sync != commit_req_seen) && frame_start) begin
                live_Ox      <= shadow_Ox;
                live_Oy      <= shadow_Oy;
                live_Oz      <= shadow_Oz;
                live_fwd_x   <= shadow_fwd_x;
                live_fwd_y   <= shadow_fwd_y;
                live_fwd_z   <= shadow_fwd_z;
                live_right_x <= shadow_right_x;
                live_right_y <= shadow_right_y;
                live_right_z <= shadow_right_z;
                live_up_x    <= shadow_up_x;
                live_up_y    <= shadow_up_y;
                live_up_z    <= shadow_up_z;

                commit_req_seen       <= commit_req_sync;
                commit_ack_toggle_pix <= commit_req_sync;
            end
        end
    end

    logic hsync_pipe [0:RENDER_LATENCY-1];
    logic vsync_pipe [0:RENDER_LATENCY-1];
    logic de_pipe    [0:RENDER_LATENCY-1];

    always_ff @(posedge clk_pix) begin
        if (!rst_pix_n) begin
            for (int i = 0; i < RENDER_LATENCY; i++) begin
                hsync_pipe[i] <= 1'b1;
                vsync_pipe[i] <= 1'b1;
                de_pipe[i]    <= 1'b0;
            end
        end else begin
            hsync_pipe[0] <= hsync;
            vsync_pipe[0] <= vsync;
            de_pipe[0]    <= active_video;

            for (int i = 1; i < RENDER_LATENCY; i++) begin
                hsync_pipe[i] <= hsync_pipe[i-1];
                vsync_pipe[i] <= vsync_pipe[i-1];
                de_pipe[i]    <= de_pipe[i-1];
            end
        end
    end

    logic [7:0] ray_r;
    logic [7:0] ray_g;
    logic [7:0] ray_b;
    logic [9:0] ray_px;
    logic [8:0] ray_py;
    logic       ray_valid;

    logic [ADDR_W-1:0]     mb_addr [N_STEPS];
    logic                  mb_re   [N_STEPS];
    logic signed [H_W-1:0] mb_dout [N_STEPS];

    logic [ADDR_W-1:0]     nb_addr [4];
    logic                  nb_re   [4];
    logic signed [H_W-1:0] nb_dout [4];

    genvar gi;
    generate
        for (gi = 0; gi < N_STEPS; gi++) begin : g_marcher_bram
            heightmap_bram #(
                .ADDR_W (ADDR_W),
                .DATA_W (H_W)
            ) u_bram (
                .clk  (clk_pix),
                .addr (mb_addr[gi]),
                .re   (mb_re[gi]),
                .dout (mb_dout[gi])
            );
        end

        for (gi = 0; gi < 4; gi++) begin : g_normal_bram
            heightmap_bram #(
                .ADDR_W (ADDR_W),
                .DATA_W (H_W)
            ) u_bram (
                .clk  (clk_pix),
                .addr (nb_addr[gi]),
                .re   (nb_re[gi]),
                .dout (nb_dout[gi])
            );
        end
    endgenerate

    design1_ray_unit #(
        .W        (W),
        .H        (H),
        .GRID_N   (GRID_N),
        .N_STEPS  (N_STEPS),
        .H_W      (H_W),
        .H_I      (2),
        .DIR_W    (DIR_W),
        .DIR_I    (2),
        .POS_W    (POS_W),
        .POS_I    (2)
    ) u_ray_unit (
        .clk                (clk_pix),
        .rst_n              (rst_pix_n),
        .en                 (1'b1),
        .Ox                 (live_Ox),
        .Oy                 (live_Oy),
        .Oz                 (live_Oz),
        .fwd_x              (live_fwd_x),
        .fwd_y              (live_fwd_y),
        .fwd_z              (live_fwd_z),
        .right_x            (live_right_x),
        .right_y            (live_right_y),
        .right_z            (live_right_z),
        .up_x               (live_up_x),
        .up_y               (live_up_y),
        .up_z               (live_up_z),
        .sun_dx             (ZERO),
        .sun_dy             (SUN_D),
        .sun_dz             (SUN_D),
        .px_in              (active_video ? sx[PX_W-1:0] : '0),
        .py_in              (active_video ? sy[PY_W-1:0] : '0),
        .valid_in           (active_video),
        .marcher_bram_addr  (mb_addr),
        .marcher_bram_re    (mb_re),
        .marcher_bram_dout  (mb_dout),
        .normal_bram_addr   (nb_addr),
        .normal_bram_re     (nb_re),
        .normal_bram_dout   (nb_dout),
        .r_out              (ray_r),
        .g_out              (ray_g),
        .b_out              (ray_b),
        .px_out             (ray_px),
        .py_out             (ray_py),
        .valid_out          (ray_valid)
    );

    logic [7:0] vid_r;
    logic [7:0] vid_g;
    logic [7:0] vid_b;

    assign vid_pVDE   = de_pipe[RENDER_LATENCY-1] & ray_valid;
    assign vid_pHSync = hsync_pipe[RENDER_LATENCY-1];
    assign vid_pVSync = vsync_pipe[RENDER_LATENCY-1];

    assign vid_r = vid_pVDE ? ray_r : 8'd0;
    assign vid_g = vid_pVDE ? ray_g : 8'd0;
    assign vid_b = vid_pVDE ? ray_b : 8'd0;

    assign vid_pData = {vid_r, vid_b, vid_g};

endmodule
