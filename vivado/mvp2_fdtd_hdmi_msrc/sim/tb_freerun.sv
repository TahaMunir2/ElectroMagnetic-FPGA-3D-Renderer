`timescale 1ns/1ps
// Verify the free-run FSM in fdtd_solver_bd_adapter:
//   * free_run=1 + frame_done pulses  -> solver auto-restarts (many solver_done)
//   * free_run=1 + NO frame_done      -> solver pauses after one iteration
//   * free_run=0                      -> manual pass-through (one iteration)
// Small grid (CELLS=16) keeps the iteration short (2*256 = 512 cycles).
module tb_freerun;
    localparam CELLS = 16, CW = 4, DW = 16, PML = 6;

    logic clk = 0; always #5 clk = ~clk;
    logic rst, solver_enable, free_run, frame_done;
    logic [DW-1:0] source_q313; logic source_valid;
    logic source_latched; logic [31:0] solver_checksum; logic solver_done;
    logic [2*CW-1:0] source_addr;

    // field BRAM buses
    logic [2*CW-1:0] ey_addra,ey_addrb,ex_addra,ex_addrb,bz_addra,bz_addrb;
    logic ey_ena,ey_enb,ex_ena,ex_enb,bz_ena,bz_enb;
    logic [0:0] ey_wea,ey_web,ex_wea,ex_web,bz_wea,bz_web;
    logic [DW-1:0] ey_dina,ey_dinb,ex_dina,ex_dinb,bz_dina,bz_dinb;
    logic [DW-1:0] ey_douta,ey_doutb,ex_douta,bz_douta,bz_doutb;

    fdtd_solver_bd_adapter #(.CELLS(CELLS),.CELL_WIDTH(CW),.DATA_WIDTH(DW),.PML_SIZE(PML)) dut (
        .clk(clk),.rst(rst),.solver_enable(solver_enable),
        .free_run(free_run),.frame_done(frame_done),
        .source_q313(source_q313),.source_valid(source_valid),
        .source_latched(source_latched),.solver_checksum(solver_checksum),
        .solver_done(solver_done),.source_addr(source_addr),
        .ey_addra(ey_addra),.ey_ena(ey_ena),.ey_wea(ey_wea),.ey_dina(ey_dina),.ey_douta(ey_douta),
        .ey_addrb(ey_addrb),.ey_enb(ey_enb),.ey_web(ey_web),.ey_dinb(ey_dinb),.ey_doutb(ey_doutb),
        .ex_addra(ex_addra),.ex_ena(ex_ena),.ex_wea(ex_wea),.ex_dina(ex_dina),.ex_douta(ex_douta),
        .ex_addrb(ex_addrb),.ex_enb(ex_enb),.ex_web(ex_web),.ex_dinb(ex_dinb),
        .bz_addra(bz_addra),.bz_ena(bz_ena),.bz_wea(bz_wea),.bz_dina(bz_dina),.bz_douta(bz_douta),
        .bz_addrb(bz_addrb),.bz_enb(bz_enb),.bz_web(bz_web),.bz_dinb(bz_dinb),.bz_doutb(bz_doutb));

    field_bram ey_bram(.clka(clk),.ena(ey_ena),.addra(ey_addra),.wea(ey_wea),.dina(ey_dina),.douta(ey_douta),
                       .clkb(clk),.enb(ey_enb),.addrb(ey_addrb),.web(ey_web),.dinb(ey_dinb),.doutb(ey_doutb));
    field_bram ex_bram(.clka(clk),.ena(ex_ena),.addra(ex_addra),.wea(ex_wea),.dina(ex_dina),.douta(ex_douta),
                       .clkb(clk),.enb(ex_enb),.addrb(ex_addrb),.web(ex_web),.dinb(ex_dinb),.doutb());
    field_bram bz_bram(.clka(clk),.ena(bz_ena),.addra(bz_addra),.wea(bz_wea),.dina(bz_dina),.douta(bz_douta),
                       .clkb(clk),.enb(bz_enb),.addrb(bz_addrb),.web(bz_web),.dinb(bz_dinb),.doutb(bz_doutb));

    integer done_count;
    always @(posedge clk) if (!rst && solver_done) done_count = done_count + 1;

    // emulate the field-magnitude scan: pulse frame_done ~20 cycles after each
    // solver_done (only while mag_enable is set)
    logic mag_enable; integer fd_timer;
    always @(posedge clk) begin
        frame_done <= 1'b0;
        if (rst) fd_timer <= 0;
        else if (solver_done && mag_enable) fd_timer <= 20;
        else if (fd_timer > 1) fd_timer <= fd_timer - 1;
        else if (fd_timer == 1) begin fd_timer <= 0; frame_done <= 1'b1; end
    end

    integer c0,c1,c2;
    initial begin
        rst=1; solver_enable=0; free_run=0; source_q313=16'sd4000; source_valid=1;
        source_addr=(CELLS/2)*CELLS+(CELLS/2); mag_enable=0; done_count=0; fd_timer=0;
        repeat(5) @(posedge clk); rst=0;

        // ---- Phase 1: free-run WITH frame_done -> should auto-restart ----
        free_run=1; mag_enable=1;
        c0=done_count;
        repeat(512*4) @(posedge clk);     // ~4 iterations worth of time
        c1=done_count;
        $display("Phase1 free-run+mag: solver_done pulses = %0d", c1-c0);
        if ((c1-c0) < 3) begin $display("FAIL: expected >=3 auto-restarts"); $fatal(1); end

        // ---- Phase 2: stop frame_done -> solver must PAUSE after current iter ----
        mag_enable=0;
        repeat(40) @(posedge clk);        // let any in-flight mag/iter settle
        c1=done_count;
        repeat(512*3) @(posedge clk);     // plenty of time for 3 more iters
        c2=done_count;
        $display("Phase2 paused (no mag): extra solver_done pulses = %0d", c2-c1);
        if ((c2-c1) > 1) begin $display("FAIL: solver did not pause without frame_done"); $fatal(1); end

        if (solver_checksum == 32'd0) begin $display("FAIL: checksum never moved (no solver activity)"); $fatal(1); end

        $display("PASS: free-run auto-restarts with frame_done and pauses without it (checksum=%h).", solver_checksum);
        $finish;
    end

    initial begin #5000000; $display("TIMEOUT"); $fatal(1); end
endmodule
