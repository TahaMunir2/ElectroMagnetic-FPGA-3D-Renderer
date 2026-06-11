// ============================================================================
//  contour_palette_axil.sv
//  ----------------------------------------------------------------------------
//  Minimal AXI4-Lite slave (8 x 32-bit register file) that drives the
//  contour_unit palette write port. The PS writes a colour-blindness-corrected
//  palette here; this slave turns each write into a {pal_we,pal_idx,pal_rgb}
//  pulse in the renderer (core) clock domain.
//
//  REGISTER MAP (AXI byte offsets):
//    0x00  REG0  CONTROL   [0]=mode (general purpose, e.g. 0=2D)   r/w
//    0x04  REG1  PAL_WR    write {idx[27:24], rgb[23:0]} -> writes palette[idx]
//                          rgb = {R[23:16],G[15:8],B[7:0]}.  Each AXI write to
//                          this offset pulses pal_we for one core cycle.
//    0x08  REG2  ...       reserved / future params (heightmap bias, etc.)
//    0x0C..0x1C REG3..7    reserved
//
//  PS usage (pseudo): for i in 0..15: write(0x04, (i<<24)|(R<<16)|(G<<8)|B)
//
//  Clocking: AXI runs on s_axi_aclk. If that differs from the renderer core
//  clock, instantiate this in the core domain (recommended: drive s_axi_aclk
//  from the same 100 MHz core clock so pal_we is glitch-free in-domain).
// ============================================================================

module contour_palette_axil #(
    parameter int C_ADDR_W = 5,   // 8 words -> 5 addr bits (byte addressed)
    parameter int C_DATA_W = 32
)(
    input  logic                  s_axi_aclk,
    input  logic                  s_axi_aresetn,

    // ---- write address ----
    input  logic [C_ADDR_W-1:0]   s_axi_awaddr,
    input  logic                  s_axi_awvalid,
    output logic                  s_axi_awready,
    // ---- write data ----
    input  logic [C_DATA_W-1:0]   s_axi_wdata,
    input  logic [C_DATA_W/8-1:0] s_axi_wstrb,
    input  logic                  s_axi_wvalid,
    output logic                  s_axi_wready,
    // ---- write response ----
    output logic [1:0]            s_axi_bresp,
    output logic                  s_axi_bvalid,
    input  logic                  s_axi_bready,
    // ---- read address ----
    input  logic [C_ADDR_W-1:0]   s_axi_araddr,
    input  logic                  s_axi_arvalid,
    output logic                  s_axi_arready,
    // ---- read data ----
    output logic [C_DATA_W-1:0]   s_axi_rdata,
    output logic [1:0]            s_axi_rresp,
    output logic                  s_axi_rvalid,
    input  logic                  s_axi_rready,

    // ---- to contour_unit palette port ----
    output logic                  pal_we,
    output logic [3:0]            pal_idx,
    output logic [23:0]           pal_rgb,

    // ---- general control bit(s) ----
    output logic                  mode
);

    localparam logic [1:0] RESP_OKAY = 2'b00;

    logic [C_DATA_W-1:0] reg0; // CONTROL

    // -------------------- write channel --------------------
    logic awr, wr;
    assign s_axi_awready = ~awr;
    assign s_axi_wready  = ~wr;

    logic [C_ADDR_W-1:0] awaddr_q;

    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            awr <= 1'b0; wr <= 1'b0;
            awaddr_q <= '0;
            s_axi_bvalid <= 1'b0; s_axi_bresp <= RESP_OKAY;
            reg0 <= '0;
            pal_we <= 1'b0; pal_idx <= '0; pal_rgb <= '0;
        end else begin
            pal_we <= 1'b0; // default: single-cycle strobe

            if (s_axi_awvalid && s_axi_awready) begin
                awr <= 1'b1; awaddr_q <= s_axi_awaddr;
            end
            if (s_axi_wvalid && s_axi_wready) wr <= 1'b1;

            // commit when both address and data have arrived
            if (awr && wr) begin
                case (awaddr_q[C_ADDR_W-1:2])
                    3'd0: reg0 <= s_axi_wdata;
                    3'd1: begin
                        pal_we  <= 1'b1;
                        pal_idx <= s_axi_wdata[27:24];
                        pal_rgb <= s_axi_wdata[23:0];
                    end
                    default: ; // reserved
                endcase
                awr <= 1'b0; wr <= 1'b0;
                s_axi_bvalid <= 1'b1; s_axi_bresp <= RESP_OKAY;
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    assign mode = reg0[0];

    // -------------------- read channel --------------------
    logic [C_ADDR_W-1:0] araddr_q;
    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rresp   <= RESP_OKAY;
            s_axi_rdata   <= '0;
            araddr_q      <= '0;
        end else begin
            s_axi_arready <= 1'b0;
            if (s_axi_arvalid && !s_axi_rvalid) begin
                s_axi_arready <= 1'b1;
                araddr_q      <= s_axi_araddr;
                s_axi_rvalid  <= 1'b1;
                case (s_axi_araddr[C_ADDR_W-1:2])
                    3'd0: s_axi_rdata <= reg0;
                    3'd1: s_axi_rdata <= {4'd0, pal_idx, pal_rgb};
                    default: s_axi_rdata <= '0;
                endcase
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

endmodule
