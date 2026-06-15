`timescale 1ns/1ps
// Verify the PS-triggered field clear zeros Ey/Ex/Bz, and that it defers while
// a magnitude scan is busy.
module tb_clear;
    localparam CELLS = 64, CW = 6, DW = 16, PML = 6, GRID = CELLS*CELLS;

    logic clk = 0; always #5 clk = ~clk;
    logic rst, solver_enable, free_run, frame_done, clear_req, mag_busy;
    logic clear_busy;
    logic signed [DW-1:0] source_q313; logic source_valid;
    logic source_latched; logic [31:0] solver_checksum; logic solver_done;
    logic [2*CW-1:0] source_addr, source_addr1, source_addr2, source_addr3;
    logic [3:0] source_en;

    logic [2*CW-1:0] ey_addra,ey_addrb,ex_addra,ex_addrb,bz_addra,bz_addrb;
    logic ey_ena,ey_enb,ex_ena,ex_enb,bz_ena,bz_enb;
    logic [0:0] ey_wea,ey_web,ex_wea,ex_web,bz_wea,bz_web;
    logic [DW-1:0] ey_dina,ey_dinb,ex_dina,ex_dinb,bz_dina,bz_dinb;
    logic [DW-1:0] ey_douta,ey_doutb,ex_douta,bz_douta,bz_doutb;

    fdtd_solver_bd_adapter #(.CELLS(CELLS),.CELL_WIDTH(CW),.DATA_WIDTH(DW),.PML_SIZE(PML)) dut (
        .clk(clk),.rst(rst),.solver_enable(solver_enable),.free_run(free_run),.frame_done(frame_done),
        .clear_req(clear_req),.mag_busy(mag_busy),.clear_busy(clear_busy),
        .source_q313(source_q313),.source_valid(source_valid),
        .source_latched(source_latched),.solver_checksum(solver_checksum),.solver_done(solver_done),
        .source_addr(source_addr),.source_addr1(source_addr1),.source_addr2(source_addr2),
        .source_addr3(source_addr3),.source_en(source_en),
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

    integer i, nonzero;
    initial begin
        // seed all fields with a nonzero pattern (simulates accumulated energy)
        for (i=0;i<4096;i=i+1) begin ey_bram.mem[i]=16'h1234; ex_bram.mem[i]=16'h2345; bz_bram.mem[i]=16'h3456; end
        rst=1; solver_enable=0; free_run=0; frame_done=0; clear_req=0; mag_busy=0;
        source_q313=0; source_valid=0; source_en=0;
        source_addr=0; source_addr1=0; source_addr2=0; source_addr3=0;
        repeat(4) @(posedge clk); rst=0; @(posedge clk);

        // Test A: clear deferred while mag_busy (drive stimulus on negedge to
        // avoid the tb/clock sampling race; PS holds clear_req high anyway)
        @(negedge clk); mag_busy=1; clear_req=1;
        repeat(10) @(posedge clk);
        if (clear_busy) begin $display("FAIL: clear started while mag_busy"); $fatal(1); end
        $display("A: clear correctly deferred during mag_busy");
        @(negedge clk); clear_req=0;   // release; re-pulse after mag idle

        // Test B: drop mag_busy, re-pulse clear -> sweep runs
        @(negedge clk); mag_busy=0;
        @(negedge clk); clear_req=1;
        @(negedge clk); clear_req=0;
        // wait for sweep to complete
        wait(clear_busy==1); wait(clear_busy==0);
        repeat(4) @(posedge clk);

        nonzero=0;
        for (i=0;i<4096;i=i+1) begin
            if (ey_bram.mem[i]!==16'h0) nonzero=nonzero+1;
            if (ex_bram.mem[i]!==16'h0) nonzero=nonzero+1;
            if (bz_bram.mem[i]!==16'h0) nonzero=nonzero+1;
        end
        $display("B: nonzero field cells after clear = %0d (of %0d)", nonzero, 3*4096);
        if (nonzero != 0) begin $display("FAIL: fields not fully cleared"); $fatal(1); end

        $display("PASS: field clear zeros Ey/Ex/Bz and defers during magnitude scan.");
        $finish;
    end
    initial begin #2000000; $display("TIMEOUT"); $fatal(1); end
endmodule
