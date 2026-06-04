// Smoke test for Design4 using the HDMI wrapper camera and mock heightmap.
// It also checks that the renderer's output coordinates remain aligned.

`timescale 1ns/1ps

module tb_ray_unit4_smoke;

    localparam int W       = 640;
    localparam int H       = 480;
    localparam int SAMPLE  = 8;
    localparam int PX_W    = 10;
    localparam int PY_W    = 9;
    localparam int GRID_N  = 64;
    localparam int IDX_W   = 6;
    localparam int ADDR_W  = IDX_W * 2;
    localparam int N_STEPS = 16;
    localparam int H_W     = 16;
    localparam int DIR_W   = 16;
    localparam int POS_W   = 16;

    localparam logic [7:0] SKY_R = 8'd135;
    localparam logic [7:0] SKY_G = 8'd206;
    localparam logic [7:0] SKY_B = 8'd235;

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

    logic [PX_W-1:0] px_in;
    logic [PY_W-1:0] py_in;
    logic            valid_in;

    logic [ADDR_W-1:0]     mb_addr [N_STEPS];
    logic                  mb_re   [N_STEPS];
    logic signed [H_W-1:0] mb_dout [N_STEPS];
    logic [ADDR_W-1:0]     nb_addr [2];
    logic                  nb_re   [2];
    logic signed [H_W-1:0] nb_dout [2];

    logic [7:0]      r_out;
    logic [7:0]      g_out;
    logic [7:0]      b_out;
    logic [PX_W-1:0] px_out;
    logic [PY_W-1:0] py_out;
    logic            valid_out;

    genvar gi;
    generate
        for (gi = 0; gi < N_STEPS; gi++) begin : g_marcher_bram
            heightmap_bram #(
                .ADDR_W        (ADDR_W),
                .DATA_W        (H_W),
                .USE_INIT_FILE (1'b0),
                .USE_MOCK_DATA (1'b1)
            ) u_bram (
                .clk  (clk),
                .addr (mb_addr[gi]),
                .re   (1'b1),
                .dout (mb_dout[gi])
            );
        end

        for (gi = 0; gi < 2; gi++) begin : g_normal_bram
            heightmap_bram #(
                .ADDR_W        (ADDR_W),
                .DATA_W        (H_W),
                .USE_INIT_FILE (1'b0),
                .USE_MOCK_DATA (1'b1)
            ) u_bram (
                .clk  (clk),
                .addr (nb_addr[gi]),
                .re   (1'b1),
                .dout (nb_dout[gi])
            );
        end
    endgenerate

    ray_unit4 #(
        .W       (W),
        .H       (H),
        .GRID_N  (GRID_N),
        .N_STEPS (N_STEPS),
        .H_W     (H_W),
        .H_I     (2),
        .DIR_W   (DIR_W),
        .DIR_I   (2),
        .POS_W   (POS_W),
        .POS_I   (2)
    ) dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .en                 (1'b1),
        .Ox                 (OX),
        .Oy                 (OY),
        .Oz                 (OZ),
        .fwd_x              (FWD_X),
        .fwd_y              (FWD_Y),
        .fwd_z              (FWD_Z),
        .right_x            (RIGHT_X),
        .right_y            (RIGHT_Y),
        .right_z            (RIGHT_Z),
        .up_x               (UP_X),
        .up_y               (UP_Y),
        .up_z               (UP_Z),
        .sun_dx             (ZERO),
        .sun_dy             (SUN_D),
        .sun_dz             (SUN_D),
        .px_in              (px_in),
        .py_in              (py_in),
        .valid_in           (valid_in),
        .marcher_bram_addr  (mb_addr),
        .marcher_bram_re    (mb_re),
        .marcher_bram_dout  (mb_dout),
        .normal_bram_addr   (nb_addr),
        .normal_bram_re     (nb_re),
        .normal_bram_dout   (nb_dout),
        .r_out              (r_out),
        .g_out              (g_out),
        .b_out              (b_out),
        .px_out             (px_out),
        .py_out             (py_out),
        .valid_out          (valid_out)
    );

    int samples_sent = 0;
    int outputs_seen = 0;
    int sky_seen = 0;
    int non_sky_seen = 0;
    int coord_errors = 0;

    task automatic feed_pixel(input int x, input int y);
        begin
            while (dut.u_marcher.phase !== 2'd0)
                @(negedge clk);

            px_in = x[PX_W-1:0];
            py_in = y[PY_W-1:0];
            valid_in = 1'b1;
            samples_sent++;

            @(negedge clk);
            valid_in = 1'b0;
        end
    endtask

    initial begin
        px_in = '0;
        py_in = '0;
        valid_in = 1'b0;

        repeat (8) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        repeat (4) @(posedge clk);
        for (int y = 0; y < H; y += SAMPLE) begin
            for (int x = 0; x < W; x += SAMPLE) begin
                feed_pixel(x, y);
            end
        end

        repeat (1000) @(posedge clk);
        $display("DESIGN4_SMOKE samples=%0d outputs=%0d sky=%0d non_sky=%0d coord_errors=%0d",
                 samples_sent, outputs_seen, sky_seen, non_sky_seen, coord_errors);

        if (outputs_seen != samples_sent)
            $fatal(1, "Renderer output count did not match input count");
        if (non_sky_seen == 0)
            $fatal(1, "All observed renderer outputs were sky color");
        if (coord_errors != 0)
            $fatal(1, "Renderer output coordinates were misaligned");

        $finish;
    end

    always_ff @(posedge clk) begin
        int expected_x;
        int expected_y;

        if (valid_out) begin
            expected_x = (outputs_seen % (W / SAMPLE)) * SAMPLE;
            expected_y = (outputs_seen / (W / SAMPLE)) * SAMPLE;

            if ((px_out != expected_x[PX_W-1:0]) ||
                (py_out != expected_y[PY_W-1:0])) begin
                if (coord_errors < 8)
                    $display("COORD_ERROR output=%0d expected=%0d,%0d actual=%0d,%0d",
                             outputs_seen, expected_x, expected_y, px_out, py_out);
                coord_errors++;
            end

            outputs_seen++;
            if ((r_out == SKY_R) && (g_out == SKY_G) && (b_out == SKY_B))
                sky_seen++;
            else
                non_sky_seen++;
        end
    end

endmodule
