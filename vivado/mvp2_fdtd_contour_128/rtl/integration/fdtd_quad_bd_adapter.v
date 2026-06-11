`timescale 1ns/1ps
// =============================================================================
//  fdtd_quad_bd_adapter.v
//
//  BD-facing wrapper around Taha's 4-lane FDTD core (fdtd_quad_core) + the
//  quad magnitude scanner. Provides the same control surface as the single-lane
//  fdtd_solver_bd_adapter so the rest of the HDMI pipeline (ping-pong, bridge,
//  renderer) is unchanged:
//    - soft source (inherited from Taha's fdtd_solver), single global source
//    - free-run FSM: run one 2048-cycle iteration, pause, scan magnitude,
//      restart on mag done
//    - PS-triggered field clear (zero all 4 lanes in parallel, 1024 cycles)
//    - rolling checksum over s_mag writes (liveness)
//    - s_mag write port out to s_mag_pingpong_ctrl
// =============================================================================
module fdtd_quad_bd_adapter #(
    parameter CELLS      = 128,
    parameter CELL_WIDTH = 7,
    parameter DATA_WIDTH = 16,
    parameter PML_SIZE   = 6
)(
    input  wire clk,
    input  wire rst,

    // source (CORDIC)
    input  wire [DATA_WIDTH-1:0]   source_q313,
    input  wire                    source_valid,
    output wire                    source_latched,
    input  wire [2*CELL_WIDTH-1:0] source_addr,

    // control
    input  wire                    solver_enable,
    input  wire                    free_run,
    input  wire [1:0]              mag_mode,
    input  wire                    clear_req,

    // CORDIC sample request: in free-run we re-time it to ONE pulse per solver
    // iteration (so the source advances exactly phase_step per injection and the
    // DC-free first-difference telescopes correctly). Else pass the PS level.
    input  wire                    ext_sample_req,
    output wire                    sample_pulse,

    // Simulation-speed throttle: extra idle cycles inserted between iterations.
    input  wire [23:0]             speed_div,
    // Moving source (Doppler / Mach cone): velocity in 1/256 cells per iteration.
    input  wire                    move_en,
    input  wire signed [15:0]      vx,
    input  wire signed [15:0]      vy,

    // status
    output wire                    solver_done,
    output wire                    mag_done,
    output wire                    mag_busy,
    output wire                    clear_busy,
    output wire [31:0]             solver_checksum,

    // s_mag write port -> s_mag_pingpong_ctrl
    output wire [2*CELL_WIDTH-1:0] s_mag_addra,
    output wire                    s_mag_ena,
    output wire [0:0]              s_mag_wea,
    output wire [DATA_WIDTH-1:0]   s_mag_dina
);
    localparam GRID_LOCAL = (CELLS*CELLS)/4;   // 1024 cells per lane

    // ---- source latch (sticky valid, like the single-lane adapter) ----
    reg [DATA_WIDTH-1:0] held_source_q313;
    reg                  held_source_valid;
    always @(posedge clk) begin
        if (rst) begin
            held_source_q313  <= {DATA_WIDTH{1'b0}};
            held_source_valid <= 1'b0;
        end else if (source_valid) begin
            held_source_q313  <= source_q313;
            held_source_valid <= 1'b1;
        end
    end
    assign source_latched = held_source_valid;

    // ---- magnitude <-> core read-back wiring ----
    wire [2*CELL_WIDTH-1:0] mag_addr;
    wire                    mag_active;
    wire signed [DATA_WIDTH-1:0] mag_ey, mag_ex, mag_bz;
    wire                    md_done;
    assign mag_done = md_done;

    // ---- clear FSM ----
    reg                    clearing;
    reg [2*CELL_WIDTH-1:0] clear_addr;
    reg                    clear_req_d;
    wire clear_start = clear_req & ~clear_req_d;
    always @(posedge clk) begin
        if (rst) begin
            clearing <= 1'b0; clear_addr <= 0; clear_req_d <= 1'b0;
        end else begin
            clear_req_d <= clear_req;
            if (!clearing) begin
                if (clear_start && !mag_busy) begin
                    clearing <= 1'b1; clear_addr <= 0;
                end
            end else begin
                if (clear_addr == GRID_LOCAL-1) clearing <= 1'b0;
                else clear_addr <= clear_addr + 1'b1;
            end
        end
    end
    assign clear_busy = clearing;

    // ---- free-run FSM (with speed throttle) ----
    //  S_SOLVE -> S_WAITMAG (magnitude scan) -> S_THROTTLE (idle speed_div
    //  cycles) -> S_SOLVE.  speed_div=0 restarts immediately (full speed).
    localparam S_SOLVE = 2'd0, S_WAITMAG = 2'd1, S_THROTTLE = 2'd2;
    reg [1:0]  fr_state;
    reg [23:0] thr_cnt;
    always @(posedge clk) begin
        if (rst) begin fr_state <= S_SOLVE; thr_cnt <= 24'd0; end
        else case (fr_state)
            S_SOLVE:    if (solver_done) fr_state <= S_WAITMAG;
            S_WAITMAG:  if (md_done) begin
                            if (speed_div == 24'd0) fr_state <= S_SOLVE;
                            else begin fr_state <= S_THROTTLE; thr_cnt <= speed_div; end
                        end
            S_THROTTLE: if (thr_cnt <= 24'd1) fr_state <= S_SOLVE;
                        else thr_cnt <= thr_cnt - 24'd1;
            default:    fr_state <= S_SOLVE;
        endcase
    end
    wire fsm_run = (fr_state == S_SOLVE);
    wire solver_enable_core = clearing ? 1'b0 :
                              (free_run ? fsm_run : solver_enable);

    // one pulse per completed iteration (magnitude done) — drives source motion
    wire iter_done = (fr_state == S_WAITMAG) && md_done;

    // re-time the CORDIC sample request to one pulse per solver iteration (on
    // solve completion), so phase advances exactly phase_step per injection.
    // The CORDIC then computes the next sample during WAITMAG/THROTTLE, ready
    // well before the next solve's counter==0 latch.
    reg solver_done_d;
    always @(posedge clk) solver_done_d <= rst ? 1'b0 : solver_done;
    wire iter_sample = solver_done & ~solver_done_d;
    assign sample_pulse = free_run ? iter_sample : ext_sample_req;

    // ---- moving source (Doppler): position accumulator, bounce off PML walls ----
    localparam integer FRAC = 8;
    localparam integer PW   = CELL_WIDTH + FRAC;
    localparam [CELL_WIDTH-1:0] LO_EDGE = PML_SIZE + 1;
    localparam [CELL_WIDTH-1:0] HI_EDGE = CELLS - PML_SIZE - 2;
    reg  [PW-1:0]       x_acc, y_acc;
    reg  signed [PW:0]  vx_cur, vy_cur;
    reg                 moving;
    wire [CELL_WIDTH-1:0] x_int = x_acc[PW-1:FRAC];
    wire [CELL_WIDTH-1:0] y_int = y_acc[PW-1:FRAC];

    always @(posedge clk) begin
        if (rst) begin
            moving <= 1'b0;
            x_acc  <= (CELLS/2) << FRAC;
            y_acc  <= (CELLS/2) << FRAC;
            vx_cur <= {(PW+1){1'b0}};
            vy_cur <= {(PW+1){1'b0}};
        end else if (move_en && !moving) begin
            // start at the static source cell, load PS velocity
            x_acc  <= {source_addr[CELL_WIDTH-1:0],            {FRAC{1'b0}}};
            y_acc  <= {source_addr[2*CELL_WIDTH-1:CELL_WIDTH], {FRAC{1'b0}}};
            vx_cur <= $signed(vx);
            vy_cur <= $signed(vy);
            moving <= 1'b1;
        end else if (!move_en) begin
            moving <= 1'b0;
        end else if (iter_done) begin
            if      (x_int <= LO_EDGE && vx_cur < 0) vx_cur <= -vx_cur;
            else if (x_int >= HI_EDGE && vx_cur > 0) vx_cur <= -vx_cur;
            else                                     x_acc  <= x_acc + vx_cur;
            if      (y_int <= LO_EDGE && vy_cur < 0) vy_cur <= -vy_cur;
            else if (y_int >= HI_EDGE && vy_cur > 0) vy_cur <= -vy_cur;
            else                                     y_acc  <= y_acc + vy_cur;
        end
    end

    wire [2*CELL_WIDTH-1:0] source_addr_eff = moving ? {y_int, x_int} : source_addr;

    // ---- rolling checksum over s_mag writes (liveness) ----
    reg [31:0] checksum_reg;
    always @(posedge clk) begin
        if (rst) checksum_reg <= 32'd0;
        else if (s_mag_wea[0])
            checksum_reg <= {checksum_reg[30:0], checksum_reg[31]}
                          ^ {s_mag_addra, s_mag_dina};
    end
    assign solver_checksum = checksum_reg;

    // ---- Taha's 4-lane FDTD core ----
    fdtd_quad_core #(
        .TOTAL_ROWS(CELLS), .COLUMNS(CELLS),
        .CELL_WIDTH(CELL_WIDTH), .DATA_WIDTH(DATA_WIDTH), .PML_SIZE(PML_SIZE)
    ) u_core (
        .clk(clk), .rst(rst),
        .source_in(held_source_q313),
        .source_valid(held_source_valid),
        .source_addr(source_addr_eff),
        .solver_enable(solver_enable_core),
        .solver_done(solver_done),
        .mag_active(mag_active),
        .mag_addr(mag_addr),
        .mag_ey(mag_ey), .mag_ex(mag_ex), .mag_bz(mag_bz),
        .clear_active(clearing),
        .clear_addr(clear_addr)
    );

    // ---- magnitude scanner (triggered by solver_done, runs while solver idle) --
    field_magnitude_quad #(
        .CELLS(CELLS), .CELL_WIDTH(CELL_WIDTH), .DATA_WIDTH(DATA_WIDTH)
    ) u_mag (
        .clk(clk), .rst(rst),
        .start(solver_done),
        .mag_mode(mag_mode),
        .busy(mag_busy),
        .done(md_done),
        .mag_addr(mag_addr), .mag_active(mag_active),
        .mag_ey(mag_ey), .mag_ex(mag_ex), .mag_bz(mag_bz),
        .s_mag_addra(s_mag_addra), .s_mag_ena(s_mag_ena),
        .s_mag_wea(s_mag_wea), .s_mag_dina(s_mag_dina)
    );

endmodule
