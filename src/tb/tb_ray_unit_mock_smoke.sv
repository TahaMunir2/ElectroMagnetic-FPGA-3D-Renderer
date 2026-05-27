// Smoke test for ray_unit using procedural mock BRAM data.
// This does not compare against a golden file; it prints the first output pixels.

`timescale 1ns/1ps

module tb_ray_unit_mock_smoke;

    localparam int W       = 16;
    localparam int H       = 16;
    localparam int PX_W    = 4;
    localparam int PY_W    = 4;
    localparam int GRID_N  = 16;
    localparam int IDX_W   = 4;
    localparam int ADDR_W  = IDX_W * 2;
    localparam int N_STEPS = 16;
    localparam int H_W     = 16;
    localparam int DIR_W   = 16;
    localparam int POS_W   = 16;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    always #5 clk = ~clk;

    logic [PX_W-1:0] px_in;
    logic [PY_W-1:0] py_in;
    logic            valid_in;

    logic [ADDR_W-1:0]     mb_addr [N_STEPS];
    logic                  mb_re   [N_STEPS];
    logic signed [H_W-1:0] mb_dout [N_STEPS];
    logic [ADDR_W-1:0]     nb_addr [4];
    logic                  nb_re   [4];
    logic signed [H_W-1:0] nb_dout [4];

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
                .re   (mb_re[gi]),
                .dout (mb_dout[gi])
            );
        end

        for (gi = 0; gi < 4; gi++) begin : g_normal_bram
            heightmap_bram #(
                .ADDR_W        (ADDR_W),
                .DATA_W        (H_W),
                .USE_INIT_FILE (1'b0),
                .USE_MOCK_DATA (1'b1)
            ) u_bram (
                .clk  (clk),
                .addr (nb_addr[gi]),
                .re   (nb_re[gi]),
                .dout (nb_dout[gi])
            );
        end
    endgenerate

    ray_unit #(
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
        .Ox                 (16'sd0),
        .Oy                 (-16'sd8192),
        .Oz                 (16'sd4096),
        .fwd_x              (16'sd0),
        .fwd_y              (16'sd8192),
        .fwd_z              (16'sd0),
        .right_x            (16'sd8192),
        .right_y            (16'sd0),
        .right_z            (16'sd0),
        .up_x               (16'sd0),
        .up_y               (16'sd0),
        .up_z               (16'sd8192),
        .sun_dx             (16'sd0),
        .sun_dy             (16'sd5793),
        .sun_dz             (16'sd5793),
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

    initial begin
        px_in = '0;
        py_in = '0;
        valid_in = 1'b0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        for (int y = 0; y < H; y++) begin
            for (int x = 0; x < W; x++) begin
                @(negedge clk);
                px_in = x[PX_W-1:0];
                py_in = y[PY_W-1:0];
                valid_in = 1'b1;
            end
        end

        @(negedge clk);
        valid_in = 1'b0;

        repeat (200) @(posedge clk);
        $finish;
    end

    always_ff @(posedge clk) begin
        if (valid_out) begin
            $display("px=%0d py=%0d rgb=%0d,%0d,%0d",
                     px_out, py_out, r_out, g_out, b_out);
        end
    end

endmodule
