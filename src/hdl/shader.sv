module shader #(
    parameter int H_W        = 16,
    parameter int H_I        = 4,
    parameter int H_F        = H_W - 1 - H_I,
    parameter int DIR_W      = 16,
    parameter int DIR_I      = 2,
    parameter int DIR_F      = DIR_W - 1 - DIR_I,
    parameter int N_STEPS    = 16,
    parameter int STEP_W     = $clog2(N_STEPS + 1),
    parameter int PX_W       = 10,
    parameter int PY_W       = 10,
    parameter logic [7:0] SKY_R = 8'd135,
    parameter logic [7:0] SKY_G = 8'd206,
    parameter logic [7:0] SKY_B = 8'd235,
    parameter logic [7:0] PALE_R   = 8'd192,
    parameter logic [7:0] PALE_G   = 8'd192,
    parameter logic [7:0] PALE_B   = 8'd192,
    parameter logic [7:0] AMBIENT  = 8'd64
)(
    input  logic                       clk,
    input  logic                       rst_n,
    input  logic                       en,

    input  logic [1:0]                 status_in,
    input  logic signed [H_W-1:0]      h_hit_in,
    input  logic [STEP_W-1:0]          step_count_in,
    input  logic signed [DIR_W-1:0]    Nx_in,
    input  logic signed [DIR_W-1:0]    Ny_in,
    input  logic signed [DIR_W-1:0]    Nz_in,
    input  logic [PX_W-1:0]            px_in,
    input  logic [PY_W-1:0]            py_in,
    input  logic                       valid_in,

    input  logic signed [DIR_W-1:0]    sun_dx,
    input  logic signed [DIR_W-1:0]    sun_dy,
    input  logic signed [DIR_W-1:0]    sun_dz,

    output logic [7:0]                 r_out,
    output logic [7:0]                 g_out,
    output logic [7:0]                 b_out,
    output logic [PX_W-1:0]            px_out,
    output logic [PY_W-1:0]            py_out,
    output logic                       valid_out
);

    localparam logic [1:0] ST_HIT = 2'b01;

    // ---- Dot product N·L ----
    logic signed [2*DIR_W-1:0] dot_x, dot_y, dot_z;
    logic signed [2*DIR_W:0]   dot_sum;
    logic signed [2*DIR_W-1:0] bright_q;

    // ---- 8-bit intermediates ----
    logic [7:0] altitude_u8;
    logic [7:0] fog_u8;
    logic [7:0] bright_u8;
    logic [7:0] light_u8;
    logic [7:0] base_r, base_g, base_b;
    logic [7:0] fogged_r, fogged_g, fogged_b;
    logic [7:0] lit_r, lit_g, lit_b;

    // ---- Scratch integers for arithmetic ----
    integer altitude_shifted;
    integer fog_int;
    integer bright_tmp;
    integer mix_r_acc, mix_g_acc, mix_b_acc;
    integer mul_r_prod, mul_g_prod, mul_b_prod;

    always_comb begin
        // =====================================================
        // BLOCK A: Lambert dot product N·L
        // =====================================================

        // Sun is hardcoded to (0, 0, 1) → dot product reduces to Nz.
        // bright_q is in the same Q-format as Nz (Q2.13).  Pad with zeros
        // on the left to match the 2*DIR_W-bit width that bright_to_u8 expects.

        if (Nz_in <= 0)
            bright_q = '0;
        else
            bright_q = {{DIR_W{1'b0}}, Nz_in};

        // =====================================================
        // BLOCK B: brightness Q-format → 8-bit, then ambient blend
        // =====================================================
        // ---- bright_to_u8 inlined ----
        if (bright_q[2*DIR_W-1])
            bright_tmp = 0;
        else if (bright_q >= (1 <<< DIR_F))
            bright_tmp = 255;
        else if (DIR_F >= 8)
            bright_tmp = bright_q >>> (DIR_F - 8);
        else
            bright_tmp = bright_q <<< (8 - DIR_F);

        // clamp_u8 inlined
        if (bright_tmp < 0)         bright_u8 = 8'd0;
        else if (bright_tmp > 255)  bright_u8 = 8'd255;
        else                        bright_u8 = bright_tmp[7:0];

        // Ambient blend: light_u8 = AMBIENT + ((255 - AMBIENT) * bright_u8) >> 8
        light_u8 = AMBIENT + (((16'd255 - AMBIENT) * bright_u8) >> 8);

        // =====================================================
        // BLOCK C: height → altitude_u8 → base RGB
        // =====================================================
        // ---- height_to_u8 inlined ----
        if (H_F >= 7)
            altitude_shifted = (h_hit_in >>> (H_F - 7)) + 128;
        else
            altitude_shifted = (h_hit_in <<< (7 - H_F)) + 128;

        // clamp_u8 inlined
        if (altitude_shifted < 0)        altitude_u8 = 8'd0;
        else if (altitude_shifted > 255) altitude_u8 = 8'd255;
        else                             altitude_u8 = altitude_shifted[7:0];

        // Height LUT: low=blue, high=red, mid=greenish
        base_r = altitude_u8;
        base_b = 8'd255 - altitude_u8;
        base_g = 8'd32 + ((8'd255 - ((altitude_u8 > 8'd127) ?
                 ((altitude_u8 - 8'd127) << 1) :
                 ((8'd127 - altitude_u8) << 1))) >> 2);

        // =====================================================
        // BLOCK D: step_count → fog
        // =====================================================
        // ---- step_to_fog inlined ----
        if (N_STEPS <= 1)
            fog_int = 0;
        else
            fog_int = (step_count_in * 255) / N_STEPS;

        // clamp_u8 inlined
        if (fog_int < 0)        fog_u8 = 8'd0;
        else if (fog_int > 255) fog_u8 = 8'd255;
        else                    fog_u8 = fog_int[7:0];

        // =====================================================
        // BLOCK E: composition — mix(base, PALE, fog) then mul(fogged, light)
        // =====================================================
        // ---- mix_u8 inlined for r/g/b ----
        mix_r_acc = ((255 - fog_u8) * base_r + fog_u8 * PALE_R) >> 8;
        mix_g_acc = ((255 - fog_u8) * base_g + fog_u8 * PALE_G) >> 8;
        mix_b_acc = ((255 - fog_u8) * base_b + fog_u8 * PALE_B) >> 8;

        // clamp_u8 inlined
        if (mix_r_acc < 0)        fogged_r = 8'd0;
        else if (mix_r_acc > 255) fogged_r = 8'd255;
        else                      fogged_r = mix_r_acc[7:0];

        if (mix_g_acc < 0)        fogged_g = 8'd0;
        else if (mix_g_acc > 255) fogged_g = 8'd255;
        else                      fogged_g = mix_g_acc[7:0];

        if (mix_b_acc < 0)        fogged_b = 8'd0;
        else if (mix_b_acc > 255) fogged_b = 8'd255;
        else                      fogged_b = mix_b_acc[7:0];

        // ---- mul_u8 inlined for r/g/b ----
        mul_r_prod = (fogged_r * light_u8) >> 8;
        mul_g_prod = (fogged_g * light_u8) >> 8;
        mul_b_prod = (fogged_b * light_u8) >> 8;

        if (mul_r_prod < 0)        lit_r = 8'd0;
        else if (mul_r_prod > 255) lit_r = 8'd255;
        else                       lit_r = mul_r_prod[7:0];

        if (mul_g_prod < 0)        lit_g = 8'd0;
        else if (mul_g_prod > 255) lit_g = 8'd255;
        else                       lit_g = mul_g_prod[7:0];

        if (mul_b_prod < 0)        lit_b = 8'd0;
        else if (mul_b_prod > 255) lit_b = 8'd255;
        else                       lit_b = mul_b_prod[7:0];
    end

    // =====================================================
    // BLOCK F: output register with MUX HIT vs sky
    // =====================================================
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