// ============================================================================
//  marcher4.sv  (Design 4: bilinear-in-marcher, quarter-rate, 1 port/step)
//  ----------------------------------------------------------------------------
//  Chains N_STEPS copies of march_step4.  Each step performs a bilinear
//  lookup (4 corners) but folds the 4 reads across 4 cycles on a SINGLE
//  dedicated BRAM port.  No sharing between steps.
//
//      N_STEPS * 1 read port  (= 48 for N_STEPS=48)
//      -> 48 independent single-port heightmap memories
//
//  A 2-bit `phase` counter (0..3) is maintained for documentation / future
//  use, but the per-step read scheduling is self-contained inside
//  march_step4 (its B0..B3 sub-stages issue the 4 corners on 4 consecutive
//  cycles).  The marcher's only timing duty is the QUARTER-RATE input gate:
//  a real pixel enters step 0 only when phase == 0, i.e. every 4 cycles.
//  This guarantees the single port of each step is never contended by two
//  in-flight real pixels of that step (real pixels are 4 cycles apart and
//  each step's read window is exactly 4 cycles).
//
//  Pipeline latency: 11 * N_STEPS cycles (march_step4 has eleven registered
//  stages: A, B0..B5, D, D2, D3, E).
//  Throughput: 1 pixel / 4 cycles.
//
//  h_hit_out is the bilinearly-interpolated surface height (smooth), as in
//  Design 3.
// ============================================================================

// ============================================================================
//  marcher32.sv  (32-step, 1px/16cyc, 8 shared ports = 4 dual-port copies)
//  ----------------------------------------------------------------------------
//  Chains N_STEPS copies of march_step32.  Each step still issues 4 corner
//  reads over 4 cycles, but the 32 steps SHARE N_PORTS=8 physical ports via
//  the collision-free schedule:
//
//        port(gi) = (gi mod 4) + 4*(gi >> 4)
//
//  proven to tile the 16-cycle window with zero slack (see read-schedule
//  table).  8 ports = 4 dual-port copies per lane = 32 BRAM tiles (128x128).
//  A sim-only $fatal collision guard machine-checks the schedule.
//
//  Feeder is 1-in-16 (one real pixel every 16 cycles).  v_chain[0] is NOT
//  re-gated on phase (ray_gen's 4-cycle latency makes valid_in arrive at a
//  nonzero phase; the upstream lane already injects 1-per-16).
//
//  Forwards the hit-cell corners (h00/h10/h01) to the downstream normal so it
//  needs no BRAM ports of its own.
// ============================================================================
module marcher32 #(
    parameter int POS_W      = 16,
    parameter int POS_I      = 4,
    parameter int POS_F      = POS_W - 1 - POS_I,

    parameter int DIR_W      = 16,
    parameter int DIR_I      = 2,
    parameter int DIR_F      = DIR_W - 1 - DIR_I,

    parameter int GRID_N     = 256,
    parameter int IDX_W      = $clog2(GRID_N),

    parameter int H_W        = 16,
    parameter int H_I        = 4,
    parameter int H_F        = H_W - 1 - H_I,

    parameter int PX_W       = 10,
    parameter int PY_W       = 10,

    parameter int N_STEPS    = 32,
    parameter int STEP_W     = $clog2(N_STEPS + 1),

    parameter int FRAC_W     = 8,

    // ----- Fold / scheduling -----
    parameter int  FOLD              = 16,   // 1 pixel / 16 cycles
    parameter int  N_PORTS           = 8,    // shared read ports = 4 dp copies
    parameter bit  INTERP_IN_MARCHER = 1'b1,

    parameter logic signed [POS_W-1:0] WORLD_HALF = (1 <<< POS_F),
    parameter logic signed [POS_W-1:0] DT         = (2 * WORLD_HALF) / GRID_N
)(
    input  logic                       clk,
    input  logic                       rst_n,
    input  logic                       en,

    input  logic signed [DIR_W-1:0]    Dx_in,
    input  logic signed [DIR_W-1:0]    Dy_in,
    input  logic signed [DIR_W-1:0]    Dz_in,
    input  logic [PX_W-1:0]            px_in,
    input  logic [PY_W-1:0]            py_in,
    input  logic                       valid_in,

    input  logic signed [POS_W-1:0]    Ox,
    input  logic signed [POS_W-1:0]    Oy,
    input  logic signed [POS_W-1:0]    Oz,

    // ----- Heightmap BRAM ports: N_PORTS shared (port(gi)=(gi%4)+4*(gi>>4)) -----
    output logic [IDX_W*2-1:0]         bram_addr [N_PORTS],
    output logic                       bram_re   [N_PORTS],
    input  logic signed [H_W-1:0]      bram_dout [N_PORTS],

    output logic [1:0]                 status_out,
    output logic [IDX_W-1:0]           ix_hit_out,
    output logic [IDX_W-1:0]           iy_hit_out,
    output logic signed [H_W-1:0]      h_hit_out,
    // hit-cell corners forwarded to normal (forward-diff, no BRAM in normal)
    output logic signed [H_W-1:0]      h00_hit_out,
    output logic signed [H_W-1:0]      h10_hit_out,
    output logic signed [H_W-1:0]      h01_hit_out,
    output logic signed [POS_W-1:0]    Px_hit_out,
    output logic signed [POS_W-1:0]    Py_hit_out,
    output logic [STEP_W-1:0]          step_count_out,
    output logic [PX_W-1:0]            px_out,
    output logic [PY_W-1:0]            py_out,
    output logic                       valid_out
);

    logic signed [POS_W-1:0]    Px_chain   [N_STEPS+1];
    logic signed [POS_W-1:0]    Py_chain   [N_STEPS+1];
    logic signed [POS_W-1:0]    Pz_chain   [N_STEPS+1];
    logic signed [DIR_W-1:0]    Dx_chain   [N_STEPS+1];
    logic signed [DIR_W-1:0]    Dy_chain   [N_STEPS+1];
    logic signed [DIR_W-1:0]    Dz_chain   [N_STEPS+1];
    logic [1:0]                 stat_chain [N_STEPS+1];
    logic                       prev_chain [N_STEPS+1];
    logic signed [H_W-1:0]      hH_chain   [N_STEPS+1];
    logic [IDX_W-1:0]           ixH_chain  [N_STEPS+1];
    logic [IDX_W-1:0]           iyH_chain  [N_STEPS+1];
    logic signed [POS_W-1:0]    PxH_chain  [N_STEPS+1];
    logic signed [POS_W-1:0]    PyH_chain  [N_STEPS+1];
    logic [STEP_W-1:0]          step_chain [N_STEPS+1];
    logic                       v_chain    [N_STEPS+1];
    // hit-cell corner chains (forwarded by march_step32)
    logic signed [H_W-1:0]      h00h_chain [N_STEPS+1];
    logic signed [H_W-1:0]      h10h_chain [N_STEPS+1];
    logic signed [H_W-1:0]      h01h_chain [N_STEPS+1];

    // per-step (unshared) read request wires; share-mux routes them to N_PORTS
    localparam int ADDR_W = IDX_W*2;
    logic [ADDR_W-1:0]     step_addr [N_STEPS];
    logic                  step_re   [N_STEPS];
    logic signed [H_W-1:0] step_dout [N_STEPS];

    // -----------------------------------------------------------------
    //  Cadence counter 0..FOLD-1.  Retained for the testbench feeder sync
    //  and documentation; it does NOT gate v_chain[0] (see below).
    // -----------------------------------------------------------------
    localparam int PHASE_W = $clog2(FOLD);
    logic [PHASE_W-1:0] phase;
    always_ff @(posedge clk) begin
        if (!rst_n)
            phase <= '0;
        else if (en)
            phase <= (phase == FOLD-1) ? '0 : phase + 1'b1;
    end

    assign Px_chain[0]   = Ox;
    assign Py_chain[0]   = Oy;
    assign Pz_chain[0]   = Oz;
    assign Dx_chain[0]   = Dx_in;
    assign Dy_chain[0]   = Dy_in;
    assign Dz_chain[0]   = Dz_in;
    assign stat_chain[0] = 2'b00;             // ST_MARCHING
    assign prev_chain[0] = 1'b0;
    assign hH_chain[0]   = '0;
    assign ixH_chain[0]  = '0;
    assign iyH_chain[0]  = '0;
    assign PxH_chain[0]  = '0;
    assign PyH_chain[0]  = '0;
    assign step_chain[0] = '0;
    assign h00h_chain[0] = '0;
    assign h10h_chain[0] = '0;
    assign h01h_chain[0] = '0;
    // Accept on valid_in alone; upstream lane injects exactly 1 pixel / FOLD.
    assign v_chain[0]    = valid_in;

    genvar gi;
    generate
        for (gi = 0; gi < N_STEPS; gi++) begin : g_march
            march_step32 #(
                .POS_W      (POS_W),
                .POS_I      (POS_I),
                .POS_F      (POS_F),
                .DIR_W      (DIR_W),
                .DIR_I      (DIR_I),
                .DIR_F      (DIR_F),
                .GRID_N     (GRID_N),
                .IDX_W      (IDX_W),
                .H_W        (H_W),
                .H_I        (H_I),
                .H_F        (H_F),
                .STEP_W     (STEP_W),
                .FRAC_W     (FRAC_W),
                .WORLD_HALF (WORLD_HALF),
                .DT         (DT)
            ) u_step (
                .clk            (clk),
                .rst_n          (rst_n),
                .en             (en),

                .Px_in          (Px_chain[gi]),
                .Py_in          (Py_chain[gi]),
                .Pz_in          (Pz_chain[gi]),
                .Dx             (Dx_chain[gi]),
                .Dy             (Dy_chain[gi]),
                .Dz             (Dz_chain[gi]),
                .status_in      (stat_chain[gi]),
                .prev_below_in  (prev_chain[gi]),
                .h_hit_in       (hH_chain[gi]),
                .ix_hit_in      (ixH_chain[gi]),
                .iy_hit_in      (iyH_chain[gi]),
                .Px_hit_in      (PxH_chain[gi]),
                .Py_hit_in      (PyH_chain[gi]),
                .step_count_in  (step_chain[gi]),
                .h00h_in        (h00h_chain[gi]),
                .h10h_in        (h10h_chain[gi]),
                .h01h_in        (h01h_chain[gi]),
                .valid_in       (v_chain[gi]),

                .bram_addr      (step_addr[gi]),
                .bram_re        (step_re[gi]),
                .bram_dout      (step_dout[gi]),

                .Px_out         (Px_chain[gi+1]),
                .Py_out         (Py_chain[gi+1]),
                .Pz_out         (Pz_chain[gi+1]),
                .Dx_out         (Dx_chain[gi+1]),
                .Dy_out         (Dy_chain[gi+1]),
                .Dz_out         (Dz_chain[gi+1]),
                .status_out     (stat_chain[gi+1]),
                .prev_below_out (prev_chain[gi+1]),
                .h_hit_out      (hH_chain[gi+1]),
                .ix_hit_out     (ixH_chain[gi+1]),
                .iy_hit_out     (iyH_chain[gi+1]),
                .Px_hit_out     (PxH_chain[gi+1]),
                .Py_hit_out     (PyH_chain[gi+1]),
                .step_count_out (step_chain[gi+1]),
                .h00h_out       (h00h_chain[gi+1]),
                .h10h_out       (h10h_chain[gi+1]),
                .h01h_out       (h01h_chain[gi+1]),
                .valid_out      (v_chain[gi+1])
            );
        end
    endgenerate

    // -----------------------------------------------------------------
    //  Read share mux: step gi -> physical port (gi mod 4) + 4*(gi >> 4).
    //  At most one step per port asserts step_re per cycle (proven), so the
    //  address select is one-hot.  Read data is broadcast back to each step.
    // -----------------------------------------------------------------
    function automatic int unsigned port_of(input int unsigned gi);
        port_of = (gi % 4) + 4*(gi / 16);
    endfunction

    always_comb begin
        for (int p = 0; p < N_PORTS; p++) begin
            bram_addr[p] = '0;
            bram_re[p]   = 1'b0;
        end
        for (int s = 0; s < N_STEPS; s++) begin
            if (step_re[s]) begin
                bram_addr[port_of(s)] = step_addr[s];   // one-hot by schedule
                bram_re[port_of(s)]   = 1'b1;
            end
        end
    end

    always_comb
        for (int s = 0; s < N_STEPS; s++)
            step_dout[s] = bram_dout[port_of(s)];

`ifndef SYNTHESIS
    // Machine-check the zero-slack schedule: a stale corner = all-sky.
    always_ff @(posedge clk) begin
        if (rst_n && en) begin
            for (int p = 0; p < N_PORTS; p++) begin
                int cnt; cnt = 0;
                for (int s = 0; s < N_STEPS; s++)
                    if (port_of(s) == p && step_re[s]) cnt++;
                if (cnt > 1)
                    $fatal(1, "[marcher32] PORT COLLISION port=%0d steps=%0d phase=%0d",
                           p, cnt, phase);
            end
        end
    end
`endif

    assign status_out     = stat_chain[N_STEPS];
    assign ix_hit_out     = ixH_chain[N_STEPS];
    assign iy_hit_out     = iyH_chain[N_STEPS];
    assign h_hit_out      = hH_chain[N_STEPS];
    assign h00_hit_out    = h00h_chain[N_STEPS];
    assign h10_hit_out    = h10h_chain[N_STEPS];
    assign h01_hit_out    = h01h_chain[N_STEPS];
    assign Px_hit_out     = PxH_chain[N_STEPS];
    assign Py_hit_out     = PyH_chain[N_STEPS];
    assign step_count_out = step_chain[N_STEPS];
    assign valid_out      = v_chain[N_STEPS];

    // -----------------------------------------------------------------
    //  Pixel-coordinate delay line. Eleven internal stages per step.
    // -----------------------------------------------------------------
    localparam int LATENCY = 11 * N_STEPS;

    logic [PX_W-1:0]  px_pipe [LATENCY];
    logic [PY_W-1:0]  py_pipe [LATENCY];

    always_ff @(posedge clk) begin
        if (en) begin
            px_pipe[0] <= px_in;
            py_pipe[0] <= py_in;
        end
    end

    genvar pi;
    generate
        for (pi = 1; pi < LATENCY; pi++) begin : g_pxpipe
            always_ff @(posedge clk) begin
                if (en) begin
                    px_pipe[pi] <= px_pipe[pi-1];
                    py_pipe[pi] <= py_pipe[pi-1];
                end
            end
        end
    endgenerate

    assign px_out = px_pipe[LATENCY-1];
    assign py_out = py_pipe[LATENCY-1];

endmodule
