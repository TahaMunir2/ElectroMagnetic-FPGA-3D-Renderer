// Full-wrapper HDMI timing regression for D4S48.
//
// The FIFO stub is deliberately always empty. HDMI timing and TMDS clock
// activity must continue, with active pixels rendered as diagnostic magenta.

`timescale 1ns/1ps

module clk_wiz_1 (
    input  logic clk_in1,
    input  logic reset,
    output logic clk_out1 = 1'b0,
    output logic clk_out2,
    output logic clk_out3 = 1'b0,
    output logic locked = 1'b0
);
    int lock_count = 0;

    assign clk_out2 = clk_in1;

    always #20 clk_out1 = ~clk_out1;
    always #5  clk_out3 = ~clk_out3;

    always_ff @(posedge clk_in1) begin
        if (reset) begin
            lock_count <= 0;
            locked <= 1'b0;
        end else if (lock_count < 8) begin
            lock_count <= lock_count + 1;
            locked <= (lock_count == 7);
        end
    end
endmodule

module rgb2dvi_0 (
    output logic       TMDS_Clk_p,
    output logic       TMDS_Clk_n,
    output logic [2:0] TMDS_Data_p,
    output logic [2:0] TMDS_Data_n,
    input  logic       aRst,
    input  logic [23:0] vid_pData,
    input  logic       vid_pVDE,
    input  logic       vid_pHSync,
    input  logic       vid_pVSync,
    input  logic       PixelClk,
    input  logic       SerialClk
);
    always_comb begin
        TMDS_Clk_p  = PixelClk & ~aRst;
        TMDS_Clk_n  = ~TMDS_Clk_p;
        TMDS_Data_p = aRst ? 3'b000
                           : {vid_pVDE, vid_pHSync, vid_pVSync};
        TMDS_Data_n = ~TMDS_Data_p;
    end
endmodule

module xpm_fifo_async #(
    parameter string FIFO_MEMORY_TYPE = "auto",
    parameter int FIFO_WRITE_DEPTH = 16,
    parameter int WRITE_DATA_WIDTH = 24,
    parameter int READ_DATA_WIDTH = 24,
    parameter string READ_MODE = "std",
    parameter int FIFO_READ_LATENCY = 1,
    parameter int PROG_FULL_THRESH = 10,
    parameter string USE_ADV_FEATURES = "0000",
    parameter int CDC_SYNC_STAGES = 2,
    parameter int RELATED_CLOCKS = 0
) (
    input  logic                         wr_clk,
    input  logic                         rst,
    input  logic                         wr_en,
    input  logic [WRITE_DATA_WIDTH-1:0]  din,
    output logic                         full,
    output logic                         prog_full,
    output logic                         wr_rst_busy,
    input  logic                         rd_clk,
    input  logic                         rd_en,
    output logic [READ_DATA_WIDTH-1:0]   dout,
    output logic                         empty,
    output logic                         rd_rst_busy,
    input  logic                         sleep,
    input  logic                         injectsbiterr,
    input  logic                         injectdbiterr,
    output logic                         almost_empty,
    output logic                         almost_full,
    output logic                         data_valid,
    output logic                         dbiterr,
    output logic                         overflow,
    output logic                         prog_empty,
    output logic [9:0]                   rd_data_count,
    output logic [9:0]                   wr_data_count,
    output logic                         sbiterr,
    output logic                         underflow,
    output logic                         wr_ack
);
    always_comb begin
        full          = 1'b0;
        prog_full     = 1'b0;
        wr_rst_busy   = 1'b0;
        dout          = '0;
        empty         = 1'b1;
        rd_rst_busy   = 1'b0;
        almost_empty  = 1'b1;
        almost_full   = 1'b0;
        data_valid    = 1'b0;
        dbiterr       = 1'b0;
        overflow      = 1'b0;
        prog_empty    = 1'b1;
        rd_data_count = '0;
        wr_data_count = '0;
        sbiterr       = 1'b0;
        underflow     = rd_en;
        wr_ack        = wr_en;
    end
endmodule

module tb_d4s48_hdmi_wrapper;
    logic clk = 1'b0;
    logic rst = 1'b0;
    logic hdmi_tx_clk_p;
    logic hdmi_tx_clk_n;
    logic [2:0] hdmi_tx_p;
    logic [2:0] hdmi_tx_n;

    int active_pixels = 0;
    int magenta_pixels = 0;
    int hsync_low_pixels = 0;
    int tmds_clock_edges = 0;

    always #4 clk = ~clk;

    ray_unit_hdmi_top_d4s48 dut (
        .clk           (clk),
        .rst           (rst),
        .hdmi_tx_clk_p (hdmi_tx_clk_p),
        .hdmi_tx_clk_n (hdmi_tx_clk_n),
        .hdmi_tx_p     (hdmi_tx_p),
        .hdmi_tx_n     (hdmi_tx_n)
    );

    always @(posedge hdmi_tx_clk_p)
        tmds_clock_edges++;

    always @(posedge dut.clk_pix) begin
        if (dut.rst_pix_n) begin
            if (dut.hdmi_de) begin
                active_pixels++;
                if ({dut.hdmi_r, dut.hdmi_g, dut.hdmi_b} == 24'hff00ff)
                    magenta_pixels++;
            end
            if (!dut.hdmi_hsync)
                hsync_low_pixels++;
        end
    end

    initial begin
        #10 rst = 1'b1;
        #100 rst = 1'b0;

        // Covers more than two complete 800-pixel lines.
        #90000;

        $display("D4S48_HDMI active=%0d magenta=%0d hsync_low=%0d tmds_edges=%0d",
                 active_pixels, magenta_pixels, hsync_low_pixels,
                 tmds_clock_edges);

        if (active_pixels == 0)
            $fatal(1, "HDMI active video never asserted while FIFO was empty");
        if (magenta_pixels != active_pixels)
            $fatal(1, "FIFO underflow did not produce diagnostic active video");
        if (hsync_low_pixels == 0)
            $fatal(1, "HDMI hsync never asserted");
        if (tmds_clock_edges == 0)
            $fatal(1, "TMDS clock never toggled");

        $finish;
    end
endmodule
