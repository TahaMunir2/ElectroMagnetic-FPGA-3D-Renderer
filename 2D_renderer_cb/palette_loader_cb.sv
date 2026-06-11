// ============================================================================
//  palette_loader.sv
//  ----------------------------------------------------------------------------
//  Standalone (no-PS) driver for the contour_unit palette write port. Lets you
//  SEE the writable palette working on the board without the PS/AXI-Lite stack.
//
//  It holds 3 preset palettes (P0 default rainbow, P1 cividis, P2 viridis from
//  palettes.svh) and, by default, auto-cycles through them every ~2^CYCLE_LOG2
//  core cycles, streaming 16 writes into {pal_we,pal_idx,pal_rgb} on each change.
//  Optionally drive `sel_in` from board switches (set use_sel_in=1).
//
//  In the real system you DELETE this and connect contour_palette_axil instead;
//  both present the identical write-port contract to contour_unit.
// ============================================================================

`include "palettes.svh"

module palette_loader #(
    parameter int CYCLE_LOG2 = 27,   // ~1.3 s per preset at 100 MHz
    parameter int N_PRESET   = 3
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        use_sel_in,   // 0 = auto-cycle, 1 = use sel_in
    input  logic [1:0]  sel_in,       // board switches (optional)

    output logic        pal_we,
    output logic [3:0]  pal_idx,
    output logic [23:0] pal_rgb
);
    // ---- preset select (auto-cycle or external) ----
    logic [CYCLE_LOG2-1:0] tick;
    logic [1:0]            sel_auto;
    logic [1:0]            sel, sel_q;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            tick <= '0; sel_auto <= 2'd0;
        end else begin
            tick <= tick + 1'b1;
            if (&tick)
                sel_auto <= (sel_auto == N_PRESET-1) ? 2'd0 : sel_auto + 2'd1;
        end
    end
    assign sel = use_sel_in ? sel_in : sel_auto;

    // ---- preset ROM lookup ----
    logic [23:0] cur;
    always_comb begin
        unique case (sel)
            2'd0:    cur = PAL_P0[k];
            2'd1:    cur = PAL_P1[k];
            default: cur = PAL_P2[k];
        endcase
    end

    // ---- write sequencer: on sel change (or startup) push 16 entries ----
    typedef enum logic {IDLE, WRITE} state_t;
    state_t state;
    logic [3:0] k;
    logic       start;

    always_ff @(posedge clk) begin
        if (!rst_n) sel_q <= 2'b11;     // force a load on first cycle
        else        sel_q <= sel;
    end
    assign start = (sel != sel_q);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE; k <= '0;
            pal_we <= 1'b0; pal_idx <= '0; pal_rgb <= '0;
        end else begin
            pal_we <= 1'b0;
            case (state)
                IDLE: if (start) begin
                    state <= WRITE; k <= '0;
                end
                WRITE: begin
                    pal_we  <= 1'b1;
                    pal_idx <= k;
                    pal_rgb <= cur;
                    if (k == 4'd15) state <= IDLE;
                    k <= k + 1'b1;
                end
            endcase
        end
    end
endmodule
