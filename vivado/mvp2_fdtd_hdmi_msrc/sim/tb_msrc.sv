`timescale 1ns/1ps
// Verify configurable multi-source injection: with a zero initial field, after
// one solve only the ENABLED source cells should be driven (~the latched sample).
module tb_msrc;
    localparam CELLS = 64, CW = 6, DW = 16, PML = 6;
    `define CELL(x,y) ((y)*CELLS + (x))

    logic clk = 0; always #5 clk = ~clk;
    logic rst, solver_enable, free_run, frame_done;
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

    integer i, a0, a1, a2, actrl;
    function integer absv(input signed [DW-1:0] v); absv = v[DW-1] ? -v : v; endfunction
    task run_one_solve;
        begin
            for (i=0;i<4096;i=i+1) begin ey_bram.mem[i]=0; ex_bram.mem[i]=0; bz_bram.mem[i]=0; end
            rst=1; solver_enable=0; @(posedge clk); @(posedge clk); rst=0; @(posedge clk);
            solver_enable=1;
            @(posedge solver_done); repeat(4) @(posedge clk);
            solver_enable=0; repeat(2) @(posedge clk);
        end
    endtask

    initial begin
        a0=`CELL(20,32); a1=`CELL(44,32); a2=`CELL(32,20); actrl=`CELL(10,10);
        source_q313=16'sd3000; source_valid=1; free_run=0; frame_done=0;
        source_addr=a0; source_addr1=a1; source_addr2=a2; source_addr3=0;

        // ---- Test 1: enable sources 0 and 1 only ----
        source_en=4'b0011;
        run_one_solve;
        $display("T1 en=0011: ey[a0]=%0d ey[a1]=%0d ey[a2]=%0d ey[ctrl]=%0d",
                 $signed(ey_bram.mem[a0]),$signed(ey_bram.mem[a1]),$signed(ey_bram.mem[a2]),$signed(ey_bram.mem[actrl]));
        if (absv(ey_bram.mem[a0]) < 1000) begin $display("FAIL: src0 not injected"); $fatal(1); end
        if (absv(ey_bram.mem[a1]) < 1000) begin $display("FAIL: src1 not injected"); $fatal(1); end
        if (absv(ey_bram.mem[a2]) > 100)  begin $display("FAIL: src2 injected but disabled"); $fatal(1); end
        if (absv(ey_bram.mem[actrl]) > 100) begin $display("FAIL: control cell nonzero"); $fatal(1); end

        // ---- Test 2: enable source 2 as well ----
        source_en=4'b0111;
        run_one_solve;
        $display("T2 en=0111: ey[a0]=%0d ey[a1]=%0d ey[a2]=%0d",
                 $signed(ey_bram.mem[a0]),$signed(ey_bram.mem[a1]),$signed(ey_bram.mem[a2]));
        if (absv(ey_bram.mem[a2]) < 1000) begin $display("FAIL: src2 not injected when enabled"); $fatal(1); end

        // ---- Test 3: disable all -> no injection ----
        source_en=4'b0000;
        run_one_solve;
        $display("T3 en=0000: ey[a0]=%0d ey[a1]=%0d", $signed(ey_bram.mem[a0]),$signed(ey_bram.mem[a1]));
        if (absv(ey_bram.mem[a0]) > 100 || absv(ey_bram.mem[a1]) > 100) begin
            $display("FAIL: injection with all sources disabled"); $fatal(1); end

        $display("PASS: multi-source injection is per-cell enable-gated and coherent.");
        $finish;
    end
    initial begin #20000000; $display("TIMEOUT"); $fatal(1); end
endmodule
