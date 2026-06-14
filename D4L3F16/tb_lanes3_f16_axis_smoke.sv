`timescale 1ns/1ps

module tb_lanes3_f16_axis_smoke;

    localparam int W = 24;
    localparam int H = 12;
    localparam int PX_W = $clog2(W);
    localparam int PY_W = $clog2(H);
    localparam int POS_W = 16;
    localparam int DIR_W = 16;

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
    localparam logic signed [DIR_W-1:0] ZERO    =  16'sd0;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    always #5 clk = ~clk;

    logic [23:0] tdata;
    logic        tvalid;
    logic        tready = 1'b1;
    logic        tuser;
    logic        tlast;
    logic [PX_W-1:0] axis_x;
    logic [PY_W-1:0] axis_y;
    logic frame_start_pulse;
    logic frame_done_pulse;
    logic reorder_overflow;

    ray_unit4_lanes3_f16_axis #(
        .W(W),
        .H(H),
        .PX_W(PX_W),
        .PY_W(PY_W),
        .GRID_N(64),
        .N_STEPS(48)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .Ox(OX), .Oy(OY), .Oz(OZ),
        .fwd_x(FWD_X), .fwd_y(FWD_Y), .fwd_z(FWD_Z),
        .right_x(RIGHT_X), .right_y(RIGHT_Y), .right_z(RIGHT_Z),
        .up_x(UP_X), .up_y(UP_Y), .up_z(UP_Z),
        .sun_dx(ZERO), .sun_dy(SUN_D), .sun_dz(SUN_D),
        .m_axis_tdata(tdata),
        .m_axis_tvalid(tvalid),
        .m_axis_tready(tready),
        .m_axis_tuser(tuser),
        .m_axis_tlast(tlast),
        .m_axis_x(axis_x),
        .m_axis_y(axis_y),
        .frame_start_pulse(frame_start_pulse),
        .frame_done_pulse(frame_done_pulse),
        .reorder_overflow(reorder_overflow)
    );

    int outputs_seen = 0;
    int coord_errors = 0;
    int user_errors = 0;
    int last_errors = 0;

    initial begin
        repeat (12) @(posedge clk);
        rst_n = 1'b1;

        wait (outputs_seen == W * H);
        @(posedge clk);

        $display("D4L3F16_AXIS outputs=%0d coord_errors=%0d user_errors=%0d last_errors=%0d overflow=%0d",
                 outputs_seen, coord_errors, user_errors, last_errors, reorder_overflow);

        if (outputs_seen != W * H)
            $fatal(1, "Did not observe one full frame");
        if (coord_errors != 0)
            $fatal(1, "Raster order mismatch");
        if (user_errors != 0)
            $fatal(1, "SOF/tuser mismatch");
        if (last_errors != 0)
            $fatal(1, "EOL/tlast mismatch");
        if (reorder_overflow)
            $fatal(1, "Reorder buffer overflowed");

        $finish;
    end

    always_ff @(posedge clk) begin
        int expected_x;
        int expected_y;

        if (rst_n && tvalid && tready) begin
            expected_x = outputs_seen % W;
            expected_y = outputs_seen / W;

            if ((axis_x != expected_x[PX_W-1:0]) ||
                (axis_y != expected_y[PY_W-1:0])) begin
                if (coord_errors < 8)
                    $display("COORD_ERROR output=%0d expected=%0d,%0d actual=%0d,%0d data=%06x",
                             outputs_seen, expected_x, expected_y, axis_x, axis_y, tdata);
                coord_errors++;
            end

            if (tuser != (outputs_seen == 0))
                user_errors++;

            if (tlast != (expected_x == W-1))
                last_errors++;

            outputs_seen++;
        end
    end

endmodule
