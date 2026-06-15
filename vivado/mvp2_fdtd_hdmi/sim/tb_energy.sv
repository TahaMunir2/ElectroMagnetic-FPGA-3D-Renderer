`timescale 1ns/1ps
// Energy-growth comparison: drives the full 64x64 solver in free-run with an
// alternating (AC) source and tracks the peak |Ey| written per iteration.
// Run twice (hard-source pingpong solver vs soft-source fdtd_hdmi solver) to
// see whether the soft source bounds the runaway the board showed.
module tb_energy;
    localparam CELLS = 64, CW = 6, DW = 16, PML = 6;
    localparam ITERS = 120;

    logic clk = 0; always #5 clk = ~clk;
    logic rst, solver_enable, free_run, frame_done;
    logic signed [DW-1:0] source_q313; logic source_valid;
    logic source_latched; logic [31:0] solver_checksum; logic solver_done;
    logic [2*CW-1:0] source_addr;

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

    // ---- peak |Ey| written this iteration ----
    integer peak;
    function integer absv(input signed [DW-1:0] v); absv = v[DW-1] ? -v : v; endfunction
    always @(posedge clk) begin
        if (!rst && ey_web && (absv(ey_dinb) > peak)) peak <= absv(ey_dinb);
    end

    // ---- free-run frame_done emulator (mag scan ~20 cyc) ----
    integer fd_timer;
    always @(posedge clk) begin
        frame_done <= 1'b0;
        if (rst) fd_timer <= 0;
        else if (solver_done) fd_timer <= 20;
        else if (fd_timer > 1) fd_timer <= fd_timer - 1;
        else if (fd_timer == 1) begin fd_timer <= 0; frame_done <= 1'b1; end
    end

    integer it, i;
    initial begin
        // zero the field memories (matches FPGA power-up)
        for (i = 0; i < 4096; i = i + 1) begin
            ey_bram.mem[i] = 0; ex_bram.mem[i] = 0; bz_bram.mem[i] = 0;
        end
        rst=1; solver_enable=0; free_run=0; frame_done=0; fd_timer=0;
        source_valid=1; source_q313=16'sd2458;       // ~0.30 in Q3.13
        source_addr=(CELLS/2)*CELLS+(CELLS/2);
        peak=0;
        repeat(5) @(posedge clk); rst=0;
        free_run=1;

        $display("iter   peak|Ey|(Q3.13)   ~float");
        for (it = 1; it <= ITERS; it = it + 1) begin
            @(posedge solver_done);
            // flip source sign each iteration -> AC drive (mimics oscillating CORDIC)
            source_q313 <= -source_q313;
            if (it % 10 == 0)
                $display("%4d        %6d          %0.3f", it, peak, peak/8192.0);
            peak <= 0;   // reset window peak
            @(posedge clk);
        end
        $display("DONE");
        $finish;
    end
    initial begin #50000000; $display("TIMEOUT"); $fatal(1); end
endmodule
