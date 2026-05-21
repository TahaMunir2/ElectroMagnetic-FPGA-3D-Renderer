// ============================================================================
//  shader.sv
//  ----------------------------------------------------------------------------
//  MVP terrain shader.
//
//  For HIT pixels, this stage:
//      - maps low altitude to blue and high altitude to red
//      - makes near hits more saturated and far hits more pale
//      - computes Lambert brightness from the incoming normal and a
//        supplied sunlight direction
//      - modulates the result with that brightness
//
//  For MISS / OFF_GRID pixels, this stage emits a simple sky colour.
//
//  Inputs are one pixel/ray result per pipeline slot from the normal stage.
//  One module instance handles the whole pixel stream over time.
//
//  Interface summary:
//      Inputs from normal:
//          status_in, h_hit_in, step_count_in,
//          Nx_in, Ny_in, Nz_in,
//          px_in, py_in, valid_in
//      Extra lighting inputs:
//          sun_dx, sun_dy, sun_dz
//      Outputs:
//          r_out, g_out, b_out, px_out, py_out, valid_out
//
//  Notes:
//      - The normal is intentionally left un-normalized by normal.sv.
//        Lighting here is therefore approximate, which is acceptable
//        for the MVP terrain renderer.
//      - step_count_in is used as a lightweight distance proxy for
//        desaturation / pale-distance fading.
//
//  Pipeline:
//      Stage 1: combinational brightness + LUT / colour math
//      Stage 2: output register
//
//  Total latency: 1 cycle
// ============================================================================

module shader #(
    // ----- Height format (must match marcher / normal) -----
    parameter int H_W        = 16,
    parameter int H_I        = 4,
    parameter int H_F        = H_W - 1 - H_I,

    // ----- Normal / sunlight format -----
    parameter int DIR_W      = 16,
    parameter int DIR_I      = 2,
    parameter int DIR_F      = DIR_W - 1 - DIR_I,

    // ----- Hit-distance proxy -----
    parameter int N_STEPS    = 16,
    parameter int STEP_W     = $clog2(N_STEPS + 1),

    // ----- Pixel coordinate widths -----
    parameter int PX_W       = 10,
    parameter int PY_W       = 10,

    // ----- Sky colour -----
    parameter logic [7:0] SKY_R = 8'd135,
    parameter logic [7:0] SKY_G = 8'd206,
    parameter logic [7:0] SKY_B = 8'd235,

    // ----- Terrain shading knobs -----
    parameter logic [7:0] PALE_R   = 8'd192,
    parameter logic [7:0] PALE_G   = 8'd192,
    parameter logic [7:0] PALE_B   = 8'd192,
    parameter logic [7:0] AMBIENT  = 8'd64
)(
    input  logic                       clk,
    input  logic                       rst_n,
    input  logic                       en,           // pipeline enable (~stall)

    // ----- From normal stage -----
    input  logic [1:0]                 status_in,    // 01=HIT, 10=OFF_GRID, 00=MISS
    input  logic signed [H_W-1:0]      h_hit_in,
    input  logic [STEP_W-1:0]          step_count_in,
    input  logic signed [DIR_W-1:0]    Nx_in,
    input  logic signed [DIR_W-1:0]    Ny_in,
    input  logic signed [DIR_W-1:0]    Nz_in,
    input  logic [PX_W-1:0]            px_in,
    input  logic [PY_W-1:0]            py_in,
    input  logic                       valid_in,

    // ----- Sunlight direction -----
    input  logic signed [DIR_W-1:0]    sun_dx,
    input  logic signed [DIR_W-1:0]    sun_dy,
    input  logic signed [DIR_W-1:0]    sun_dz,

    // ----- To emit / framebuffer stage -----
    output logic [7:0]                 r_out,
    output logic [7:0]                 g_out,
    output logic [7:0]                 b_out,
    output logic [PX_W-1:0]            px_out,
    output logic [PY_W-1:0]            py_out,
    output logic                       valid_out
);

    localparam logic [1:0] ST_MISS     = 2'b00;
    localparam logic [1:0] ST_HIT      = 2'b01;
    localparam logic [1:0] ST_OFFGRID  = 2'b10;

    function automatic logic [7:0] clamp_u8 (
        input integer v
    );
        if (v < 0)
            return 8'd0;
        else if (v > 255)
            return 8'd255;
        else
            return v[7:0];
    endfunction

    function automatic logic [7:0] mix_u8 (
        input logic [7:0] a,
        input logic [7:0] b,
        input logic [7:0] t
    );
        integer acc;
        begin
            acc = ((255 - t) * a + t * b) >> 8;
            return clamp_u8(acc);
        end
    endfunction

    function automatic logic [7:0] mul_u8 (
        input logic [7:0] a,
        input logic [7:0] b
    );
        integer prod;
        begin
            prod = (a * b) >> 8;
            return clamp_u8(prod);
        end
    endfunction

    function automatic logic [7:0] height_to_u8 (
        input logic signed [H_W-1:0] h
    );
        integer shifted;
        begin
            // Map signed height roughly into [0,255] with 0 height near mid-range.
            if (H_F >= 7)
                shifted = (h >>> (H_F - 7)) + 128;
            else
                shifted = (h <<< (7 - H_F)) + 128;
            return clamp_u8(shifted);
        end
    endfunction

    function automatic logic [7:0] step_to_fog (
        input logic [STEP_W-1:0] step_count
    );
        integer fog;
        begin
            if (N_STEPS <= 1)
                fog = 0;
            else
                fog = (step_count * 255) / N_STEPS;
            return clamp_u8(fog);
        end
    endfunction

    function automatic logic [7:0] bright_to_u8 (
        input logic signed [2*DIR_W-1:0] bright_q
    );
        integer tmp;
        begin
            // Clamp Q2.13-ish brightness to [0,1] and convert to 8-bit.
            if (bright_q[2*DIR_W-1])
                tmp = 0;
            else if (bright_q >= (1 <<< DIR_F))
                tmp = 255;
            else if (DIR_F >= 8)
                tmp = bright_q >>> (DIR_F - 8);
            else
                tmp = bright_q <<< (8 - DIR_F);
            return clamp_u8(tmp);
        end
    endfunction

    logic [7:0] altitude_u8;
    logic [7:0] fog_u8;
    logic [7:0] bright_u8;
    logic [7:0] light_u8;
    logic signed [2*DIR_W-1:0] dot_x;
    logic signed [2*DIR_W-1:0] dot_y;
    logic signed [2*DIR_W-1:0] dot_z;
    logic signed [2*DIR_W:0]   dot_sum;
    logic signed [2*DIR_W-1:0] bright_q;

    logic [7:0] base_r, base_g, base_b;
    logic [7:0] fogged_r, fogged_g, fogged_b;
    logic [7:0] lit_r, lit_g, lit_b;

    always_comb begin
        dot_x = Nx_in * sun_dx;
        dot_y = Ny_in * sun_dy;
        dot_z = Nz_in * sun_dz;
        dot_sum = dot_x + dot_y + dot_z;

        if (dot_sum <= 0)
            bright_q = '0;
        else
            bright_q = dot_sum >>> DIR_F;

        altitude_u8 = height_to_u8(h_hit_in);
        fog_u8      = step_to_fog(step_count_in);
        bright_u8   = bright_to_u8(bright_q);

        // Add ambient so terrain is never fully black.
        light_u8 = AMBIENT + ((8'd255 - AMBIENT) * bright_u8 >> 8);

        // Height LUT: low = blue, high = red, middle = a bit greener.
        base_r = altitude_u8;
        base_b = 8'd255 - altitude_u8;
        base_g = 8'd32 + ((8'd255 - ((altitude_u8 > 8'd127) ?
                 ((altitude_u8 - 8'd127) << 1) :
                 ((8'd127 - altitude_u8) << 1))) >> 2);

        // Distance fade: far terrain mixes toward a pale colour.
        fogged_r = mix_u8(base_r, PALE_R, fog_u8);
        fogged_g = mix_u8(base_g, PALE_G, fog_u8);
        fogged_b = mix_u8(base_b, PALE_B, fog_u8);

        lit_r = mul_u8(fogged_r, light_u8);
        lit_g = mul_u8(fogged_g, light_u8);
        lit_b = mul_u8(fogged_b, light_u8);
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
        end else if (en) begin
            px_out    <= px_in;
            py_out    <= py_in;
            valid_out <= valid_in;

            if (status_in == ST_HIT) begin
                r_out <= lit_r;
                g_out <= lit_g;
                b_out <= lit_b;
            end else begin
                r_out <= SKY_R;
                g_out <= SKY_G;
                b_out <= SKY_B;
            end
        end
    end

endmodule
