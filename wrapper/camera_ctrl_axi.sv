// AXI4-Lite camera register block.
//
// Register map, 32-bit words:
//   0x00 control: write bit 0 = request commit at next video frame
//   0x04 status : bit 0 = commit pending
//   0x10 Ox       0x14 Oy       0x18 Oz
//   0x20 fwd_x    0x24 fwd_y    0x28 fwd_z
//   0x30 right_x  0x34 right_y  0x38 right_z
//   0x40 up_x     0x44 up_y     0x48 up_z
//
// Camera values are signed Q2.13 in the low 16 bits of each register.

module camera_ctrl_axi #(
    parameter int ADDR_W = 7
)(
    input  logic        s_axi_aclk,
    input  logic        s_axi_aresetn,

    input  logic [ADDR_W-1:0] s_axi_awaddr,
    input  logic [2:0]        s_axi_awprot,
    input  logic              s_axi_awvalid,
    output logic              s_axi_awready,

    input  logic [31:0]       s_axi_wdata,
    input  logic [3:0]        s_axi_wstrb,
    input  logic              s_axi_wvalid,
    output logic              s_axi_wready,

    output logic [1:0]        s_axi_bresp,
    output logic              s_axi_bvalid,
    input  logic              s_axi_bready,

    input  logic [ADDR_W-1:0] s_axi_araddr,
    input  logic [2:0]        s_axi_arprot,
    input  logic              s_axi_arvalid,
    output logic              s_axi_arready,

    output logic [31:0]       s_axi_rdata,
    output logic [1:0]        s_axi_rresp,
    output logic              s_axi_rvalid,
    input  logic              s_axi_rready,

    input  logic              commit_ack_toggle,
    output logic              commit_req_toggle,
    output logic signed [15:0] shadow_Ox,
    output logic signed [15:0] shadow_Oy,
    output logic signed [15:0] shadow_Oz,
    output logic signed [15:0] shadow_fwd_x,
    output logic signed [15:0] shadow_fwd_y,
    output logic signed [15:0] shadow_fwd_z,
    output logic signed [15:0] shadow_right_x,
    output logic signed [15:0] shadow_right_y,
    output logic signed [15:0] shadow_right_z,
    output logic signed [15:0] shadow_up_x,
    output logic signed [15:0] shadow_up_y,
    output logic signed [15:0] shadow_up_z
);

    localparam logic signed [15:0] DEFAULT_OX      = -16'sd2867;
    localparam logic signed [15:0] DEFAULT_OY      = -16'sd2867;
    localparam logic signed [15:0] DEFAULT_OZ      =  16'sd3686;
    localparam logic signed [15:0] DEFAULT_FWD_X   =  16'sd4096;
    localparam logic signed [15:0] DEFAULT_FWD_Y   =  16'sd4096;
    localparam logic signed [15:0] DEFAULT_FWD_Z   = -16'sd5793;
    localparam logic signed [15:0] DEFAULT_RIGHT_X =  16'sd5793;
    localparam logic signed [15:0] DEFAULT_RIGHT_Y = -16'sd5793;
    localparam logic signed [15:0] DEFAULT_RIGHT_Z =  16'sd0;
    localparam logic signed [15:0] DEFAULT_UP_X    =  16'sd4096;
    localparam logic signed [15:0] DEFAULT_UP_Y    =  16'sd4096;
    localparam logic signed [15:0] DEFAULT_UP_Z    =  16'sd5793;

    logic [ADDR_W-1:0] awaddr_r;
    logic [31:0]       wdata_r;
    logic              aw_have;
    logic              w_have;
    (* ASYNC_REG = "TRUE" *) logic ack_meta;
    (* ASYNC_REG = "TRUE" *) logic ack_sync;

    assign s_axi_bresp = 2'b00;
    assign s_axi_rresp = 2'b00;

    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_awready    <= 1'b0;
            s_axi_wready     <= 1'b0;
            s_axi_bvalid     <= 1'b0;
            s_axi_arready    <= 1'b0;
            s_axi_rvalid     <= 1'b0;
            s_axi_rdata      <= 32'd0;
            commit_req_toggle <= 1'b0;
            ack_meta         <= 1'b0;
            ack_sync         <= 1'b0;
            awaddr_r         <= '0;
            wdata_r          <= '0;
            aw_have          <= 1'b0;
            w_have           <= 1'b0;

            shadow_Ox      <= DEFAULT_OX;
            shadow_Oy      <= DEFAULT_OY;
            shadow_Oz      <= DEFAULT_OZ;
            shadow_fwd_x   <= DEFAULT_FWD_X;
            shadow_fwd_y   <= DEFAULT_FWD_Y;
            shadow_fwd_z   <= DEFAULT_FWD_Z;
            shadow_right_x <= DEFAULT_RIGHT_X;
            shadow_right_y <= DEFAULT_RIGHT_Y;
            shadow_right_z <= DEFAULT_RIGHT_Z;
            shadow_up_x    <= DEFAULT_UP_X;
            shadow_up_y    <= DEFAULT_UP_Y;
            shadow_up_z    <= DEFAULT_UP_Z;
        end else begin
            ack_meta <= commit_ack_toggle;
            ack_sync <= ack_meta;

            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_arready <= 1'b0;

            if (!s_axi_bvalid && !aw_have && s_axi_awvalid) begin
                s_axi_awready <= 1'b1;
                awaddr_r      <= s_axi_awaddr;
                aw_have       <= 1'b1;
            end

            if (!s_axi_bvalid && !w_have && s_axi_wvalid) begin
                s_axi_wready <= 1'b1;
                wdata_r      <= s_axi_wdata;
                w_have       <= 1'b1;
            end

            if (!s_axi_bvalid && aw_have && w_have) begin
                s_axi_bvalid <= 1'b1;
                aw_have      <= 1'b0;
                w_have       <= 1'b0;

                unique case (awaddr_r[6:0])
                    7'h00: begin
                        if (wdata_r[0])
                            commit_req_toggle <= ~commit_req_toggle;
                    end
                    7'h10: shadow_Ox      <= wdata_r[15:0];
                    7'h14: shadow_Oy      <= wdata_r[15:0];
                    7'h18: shadow_Oz      <= wdata_r[15:0];
                    7'h20: shadow_fwd_x   <= wdata_r[15:0];
                    7'h24: shadow_fwd_y   <= wdata_r[15:0];
                    7'h28: shadow_fwd_z   <= wdata_r[15:0];
                    7'h30: shadow_right_x <= wdata_r[15:0];
                    7'h34: shadow_right_y <= wdata_r[15:0];
                    7'h38: shadow_right_z <= wdata_r[15:0];
                    7'h40: shadow_up_x    <= wdata_r[15:0];
                    7'h44: shadow_up_y    <= wdata_r[15:0];
                    7'h48: shadow_up_z    <= wdata_r[15:0];
                    default: begin
                    end
                endcase
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            if (!s_axi_rvalid && s_axi_arvalid) begin
                s_axi_arready <= 1'b1;
                s_axi_rvalid  <= 1'b1;

                unique case (s_axi_araddr[6:0])
                    7'h00: s_axi_rdata <= 32'd0;
                    7'h04: s_axi_rdata <= {31'd0, commit_req_toggle ^ ack_sync};
                    7'h10: s_axi_rdata <= {{16{shadow_Ox[15]}}, shadow_Ox};
                    7'h14: s_axi_rdata <= {{16{shadow_Oy[15]}}, shadow_Oy};
                    7'h18: s_axi_rdata <= {{16{shadow_Oz[15]}}, shadow_Oz};
                    7'h20: s_axi_rdata <= {{16{shadow_fwd_x[15]}}, shadow_fwd_x};
                    7'h24: s_axi_rdata <= {{16{shadow_fwd_y[15]}}, shadow_fwd_y};
                    7'h28: s_axi_rdata <= {{16{shadow_fwd_z[15]}}, shadow_fwd_z};
                    7'h30: s_axi_rdata <= {{16{shadow_right_x[15]}}, shadow_right_x};
                    7'h34: s_axi_rdata <= {{16{shadow_right_y[15]}}, shadow_right_y};
                    7'h38: s_axi_rdata <= {{16{shadow_right_z[15]}}, shadow_right_z};
                    7'h40: s_axi_rdata <= {{16{shadow_up_x[15]}}, shadow_up_x};
                    7'h44: s_axi_rdata <= {{16{shadow_up_y[15]}}, shadow_up_y};
                    7'h48: s_axi_rdata <= {{16{shadow_up_z[15]}}, shadow_up_z};
                    default: s_axi_rdata <= 32'd0;
                endcase
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

endmodule
