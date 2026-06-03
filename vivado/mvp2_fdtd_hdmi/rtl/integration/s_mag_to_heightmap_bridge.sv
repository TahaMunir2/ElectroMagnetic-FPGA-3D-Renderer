`timescale 1ns/1ps
// =============================================================================
//  s_mag_to_heightmap_bridge.sv
//
//  Bridges the FDTD ping-pong s_mag buffers to the renderer's heightmap BRAMs.
//
//  Both the s_mag buffers and the heightmap are 64x64 (4096 cells), so this is
//  a straight cell-for-cell copy — no downsampling — with a magnitude->height
//  scale (right shift).
//
//  Tear-free on BOTH sides:
//    * Producer side : it reads the s_mag FRONT buffer (selected by read_sel
//      from the ping-pong controller), which the ping-pong guarantees is a
//      complete, stable frame.  read_sel is LATCHED at the start of each burst
//      so a mid-burst buffer swap can't switch the source under us.
//    * Consumer side : it writes the 52 single-buffered heightmap BRAMs ONLY
//      during vertical blanking (vblank=1), when the renderer issues no reads.
//      A guard delay lets the render pipeline (RENDER_LATENCY) drain first.
//
//  One burst per display vblank: it always copies whatever the current front
//  buffer holds.  If the FDTD runs faster than the display it drops frames; if
//  slower it re-copies the same frame.  Either way the displayed heightmap is
//  always internally consistent.
//
//  All logic is in the clk_pix (25 MHz) domain — same as the FDTD datapath and
//  the renderer — so there is no clock-domain crossing on the heightmap path.
// =============================================================================
module s_mag_to_heightmap_bridge #(
    parameter int ADDR_W       = 12,   // 4096 cells
    parameter int DATA_W       = 16,
    parameter int GUARD_CYCLES = 256,  // wait for render pipeline to drain
    parameter int HEIGHT_SHIFT = 1     // |E|/|S| magnitude -> terrain height
)(
    input  logic                     clk,
    input  logic                     rst,        // active-high

    // Runtime height scale (signed): >0 = left-shift (amplify), <0 = right-shift
    // (attenuate), 0 = pass through. Lets the PS tune terrain height live without
    // a rebuild. 5-bit signed, range -16..+15.
    input  logic signed [4:0]        height_ctl,

    // Render-side timing
    input  logic                     vblank,     // high during vertical blank

    // s_mag ping-pong read side (port B of both buffers)
    input  logic                     read_sel,   // 0 = buffer A is front, 1 = B
    output logic [ADDR_W-1:0]        s_mag_addrb,
    output logic                     s_mag_enb,
    input  logic signed [DATA_W-1:0] s_mag_a_doutb,
    input  logic signed [DATA_W-1:0] s_mag_b_doutb,

    // Heightmap write side — broadcast to all 52 heightmap BRAMs
    output logic                     hm_we,
    output logic [ADDR_W-1:0]        hm_waddr,
    output logic signed [DATA_W-1:0] hm_wdata,

    // Status
    output logic                     busy
);
    localparam int DEPTH    = 1 << ADDR_W;
    localparam [ADDR_W-1:0] LAST = DEPTH - 1;

    typedef enum logic [1:0] {S_IDLE, S_GUARD, S_BURST} state_t;
    state_t st;

    logic                     vblank_d;
    logic [$clog2(GUARD_CYCLES+1)-1:0] guard;
    logic                     sel_l;        // latched read_sel for this burst

    logic [ADDR_W-1:0]        rd_addr;      // address being issued this cycle
    logic                     issuing;      // still issuing read addresses

    // 1-deep pipeline matching the BRAM's 1-cycle read latency.
    // s_mag_addrb/enb are COMBINATIONAL (see below) so the only latency on the
    // read path is the BRAM's own 1-cycle register — matched by this one stage.
    logic [ADDR_W-1:0]        wr_addr_d;
    logic                     wr_valid_d;

    // Front-buffer data (registered doutb arrives 1 cycle after addrb)
    wire signed [DATA_W-1:0] front_dout = sel_l ? s_mag_b_doutb : s_mag_a_doutb;

    // Combinational read address/enable into the s_mag BRAM port B.
    always_comb begin
        s_mag_addrb = rd_addr;
        s_mag_enb   = (st == S_BURST) && issuing;
    end

    // Sign-preserving runtime scale.  height_ctl > 0 amplifies (arithmetic left
    // shift), < 0 attenuates (arithmetic right shift), 0 = pass-through.
    // Works for both data kinds the field-magnitude unit produces:
    //   * |E| / |S| magnitudes  -> non-negative, stay positive (hills only).
    //   * raw signed Ey (wave)  -> sign kept, so valleys render below the plane.
    // Saturates symmetrically to the signed 16-bit range.
    function automatic logic signed [DATA_W-1:0] scale_height(
            input logic signed [DATA_W-1:0] m,
            input logic signed [4:0]        ctl);
        logic signed [2*DATA_W-1:0] wide;
        logic [4:0]                 amt;
        localparam signed [2*DATA_W-1:0] HMAX =  (1 <<< (DATA_W-1)) - 1; // +32767
        localparam signed [2*DATA_W-1:0] HMIN = -(1 <<< (DATA_W-1));     // -32768
        begin
            if (ctl >= 0) begin
                amt  = ctl;
                wide = $signed(m) <<< amt;        // amplify, sign preserved
            end else begin
                amt  = -ctl;
                wide = $signed(m) >>> amt;        // attenuate, arithmetic
            end
            if (wide > HMAX)      scale_height = HMAX[DATA_W-1:0];
            else if (wide < HMIN) scale_height = HMIN[DATA_W-1:0];
            else                  scale_height = wide[DATA_W-1:0];
        end
    endfunction

    always_ff @(posedge clk) begin
        if (rst) begin
            st         <= S_IDLE;
            vblank_d   <= 1'b0;
            guard      <= '0;
            sel_l      <= 1'b0;
            rd_addr    <= '0;
            issuing    <= 1'b0;
            wr_addr_d  <= '0;
            wr_valid_d <= 1'b0;
            hm_we      <= 1'b0;
            hm_waddr   <= '0;
            hm_wdata   <= '0;
        end else begin
            vblank_d   <= vblank;
            // defaults each cycle
            hm_we      <= 1'b0;
            wr_valid_d <= 1'b0;

            case (st)
                // ----------------------------------------------------------
                S_IDLE: begin
                    // trigger on vblank rising edge
                    if (vblank && !vblank_d) begin
                        sel_l <= read_sel;     // snapshot the front buffer choice
                        guard <= '0;
                        st    <= S_GUARD;
                    end
                end
                // ----------------------------------------------------------
                S_GUARD: begin
                    // let the render pipeline finish draining the last active line
                    if (guard == GUARD_CYCLES[$clog2(GUARD_CYCLES+1)-1:0]) begin
                        rd_addr <= '0;
                        issuing <= 1'b1;       // S_BURST issues cell 0 next cycle
                        st      <= S_BURST;
                    end else begin
                        guard <= guard + 1'b1;
                    end
                end
                // ----------------------------------------------------------
                S_BURST: begin
                    // issue successive read addresses (addrb/enb are combinational
                    // off rd_addr/issuing; data lands 1 cycle later in front_dout)
                    if (issuing) begin
                        // remember the address whose data lands next cycle
                        wr_addr_d   <= rd_addr;
                        wr_valid_d  <= 1'b1;
                        if (rd_addr == LAST)
                            issuing <= 1'b0;
                        else
                            rd_addr <= rd_addr + 1'b1;
                    end

                    // write the cell whose read was issued last cycle
                    if (wr_valid_d) begin
                        hm_we    <= 1'b1;
                        hm_waddr <= wr_addr_d;
                        hm_wdata <= scale_height(front_dout, height_ctl);
                        if (wr_addr_d == LAST)
                            st <= S_IDLE;       // last cell written -> done
                    end
                end
                default: st <= S_IDLE;
            endcase
        end
    end

    assign busy = (st != S_IDLE);

endmodule
