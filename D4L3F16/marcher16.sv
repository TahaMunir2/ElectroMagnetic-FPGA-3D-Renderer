// ============================================================================
//  marcher16.sv
//  ----------------------------------------------------------------------------
//  Design4-compatible marcher with a 16-cycle input interval.
//
//  Each march_step4 still performs the same four-cycle bilinear height lookup as
//  D4S48.  The difference is that the 16-cycle launch interval lets four
//  non-overlapping march steps share one physical heightmap BRAM read port.
//
//      D4S48:   48 step ports, 1 pixel / 4 cycles
//      F16:     12 step ports, 1 pixel / 16 cycles
//
//  The grouping below is a static coloring of the step read windows.  Adjacent
//  steps are separated by march_step4's 11-cycle latency; with a modulo-16 input
//  interval this produces non-overlapping four-cycle read windows inside each
//  group.  The arithmetic datapath is unchanged.
// ============================================================================

module marcher16 #(
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

    parameter int N_STEPS    = 48,
    parameter int STEP_W     = $clog2(N_STEPS + 1),
    parameter int FRAC_W     = 8,

    parameter int FOLD       = 16,
    parameter int BRAM_PORTS = 12,

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

    output logic [IDX_W*2-1:0]         bram_addr [BRAM_PORTS],
    output logic                       bram_re   [BRAM_PORTS],
    input  logic signed [H_W-1:0]      bram_dout [BRAM_PORTS],

    output logic [1:0]                 status_out,
    output logic [IDX_W-1:0]           ix_hit_out,
    output logic [IDX_W-1:0]           iy_hit_out,
    output logic signed [H_W-1:0]      h_hit_out,
    output logic signed [POS_W-1:0]    Px_hit_out,
    output logic signed [POS_W-1:0]    Py_hit_out,
    output logic [STEP_W-1:0]          step_count_out,
    output logic [PX_W-1:0]            px_out,
    output logic [PY_W-1:0]            py_out,
    output logic                       valid_out,
    output logic [$clog2(FOLD)-1:0]    phase_out
);

    function automatic int port_for_step(input int step);
        begin
            unique case (step)
                0, 12,  8,  4: port_for_step = 0;
               16, 28, 24, 20: port_for_step = 1;
               32, 44, 40, 36: port_for_step = 2;
                3, 15, 11,  7: port_for_step = 3;
               19, 31, 27, 23: port_for_step = 4;
               35, 47, 43, 39: port_for_step = 5;
                6,  2, 14, 10: port_for_step = 6;
               22, 18, 30, 26: port_for_step = 7;
               38, 34, 46, 42: port_for_step = 8;
                9,  5,  1, 13: port_for_step = 9;
               25, 21, 17, 29: port_for_step = 10;
               41, 37, 33, 45: port_for_step = 11;
                default:        port_for_step = 0;
            endcase
        end
    endfunction

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

    logic [IDX_W*2-1:0]         step_bram_addr [N_STEPS];
    logic                       step_bram_re   [N_STEPS];
    logic signed [H_W-1:0]      step_bram_dout [N_STEPS];

    logic [$clog2(FOLD)-1:0] phase;
    always_ff @(posedge clk) begin
        if (!rst_n)
            phase <= '0;
        else if (en)
            phase <= phase + 1'b1;
    end
    assign phase_out = phase;

    assign Px_chain[0]   = Ox;
    assign Py_chain[0]   = Oy;
    assign Pz_chain[0]   = Oz;
    assign Dx_chain[0]   = Dx_in;
    assign Dy_chain[0]   = Dy_in;
    assign Dz_chain[0]   = Dz_in;
    assign stat_chain[0] = 2'b00;
    assign prev_chain[0] = 1'b0;
    assign hH_chain[0]   = '0;
    assign ixH_chain[0]  = '0;
    assign iyH_chain[0]  = '0;
    assign PxH_chain[0]  = '0;
    assign PyH_chain[0]  = '0;
    assign step_chain[0] = '0;
    assign v_chain[0]    = valid_in && (phase == '0);

    genvar gi;
    generate
        for (gi = 0; gi < N_STEPS; gi++) begin : g_march
            localparam int PORT = port_for_step(gi);
            assign step_bram_dout[gi] = bram_dout[PORT];

            march_step4 #(
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
                .valid_in       (v_chain[gi]),
                .bram_addr      (step_bram_addr[gi]),
                .bram_re        (step_bram_re[gi]),
                .bram_dout      (step_bram_dout[gi]),
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
                .valid_out      (v_chain[gi+1])
            );
        end

        for (gi = 0; gi < BRAM_PORTS; gi++) begin : g_port_mux
            always_comb begin
                bram_addr[gi] = '0;
                bram_re[gi]   = 1'b0;
                for (int si = 0; si < N_STEPS; si++) begin
                    if ((port_for_step(si) == gi) && step_bram_re[si]) begin
                        bram_addr[gi] = step_bram_addr[si];
                        bram_re[gi]   = 1'b1;
                    end
                end
            end
        end
    endgenerate

    assign status_out     = stat_chain[N_STEPS];
    assign ix_hit_out     = ixH_chain[N_STEPS];
    assign iy_hit_out     = iyH_chain[N_STEPS];
    assign h_hit_out      = hH_chain[N_STEPS];
    assign Px_hit_out     = PxH_chain[N_STEPS];
    assign Py_hit_out     = PyH_chain[N_STEPS];
    assign step_count_out = step_chain[N_STEPS];
    assign valid_out      = v_chain[N_STEPS];

    localparam int LATENCY = 11 * N_STEPS;

    logic [PX_W-1:0] px_pipe [LATENCY];
    logic [PY_W-1:0] py_pipe [LATENCY];

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
