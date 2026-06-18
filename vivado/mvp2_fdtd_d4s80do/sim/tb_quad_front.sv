`timescale 1ns/1ps
module tb_quad_front;
  localparam DW=16, CW=6;
  logic clk=0; always #5 clk=~clk;
  logic rst;
  logic [DW-1:0] source_q313; logic source_valid; logic source_latched;
  logic [2*CW-1:0] source_addr;
  logic solver_enable, free_run; logic [1:0] mag_mode; logic clear_req;
  logic solver_done, mag_done, mag_busy, clear_busy; logic [31:0] checksum;
  logic [2*CW-1:0] s_addr; logic s_ena; logic [0:0] s_wea; logic [DW-1:0] s_din;

  fdtd_quad_bd_adapter dut(.clk(clk),.rst(rst),
    .source_q313(source_q313),.source_valid(source_valid),.source_latched(source_latched),.source_addr(source_addr),
    .solver_enable(solver_enable),.free_run(free_run),.mag_mode(mag_mode),.clear_req(clear_req),
    .solver_done(solver_done),.mag_done(mag_done),.mag_busy(mag_busy),.clear_busy(clear_busy),.solver_checksum(checksum),
    .s_mag_addra(s_addr),.s_mag_ena(s_ena),.s_mag_wea(s_wea),.s_mag_dina(s_din));

  // capture s_mag frame
  logic signed [DW-1:0] smag [0:4095];
  always @(posedge clk) if (s_wea[0]) smag[s_addr] <= s_din;

  integer frames=0, i, nonzero;
  always @(posedge clk) if (!rst && mag_done) frames <= frames + 1;

  initial begin
    for (i=0;i<4096;i=i+1) smag[i]=0;
    rst=1; source_q313=16'sd3000; source_valid=1; source_addr=12'd2080; // center
    solver_enable=0; free_run=1; mag_mode=2; clear_req=0;  // signed-Ey view
    repeat(6) @(posedge clk); rst=0;
    // run ~6 frames
    wait(frames==6);
    @(posedge clk);
    // check: source cell + neighbours nonzero, checksum moved
    nonzero=0;
    for (i=2000;i<2160;i=i+1) if (smag[i]!==0) nonzero=nonzero+1;
    $display("frames=%0d  checksum=%h  smag[2080]=%0d  nonzero(center band)=%0d",
             frames, checksum, $signed(smag[2080]), nonzero);
    if (checksum==0)   begin $display("FAIL: checksum never moved"); $finish; end
    if (nonzero < 5)   begin $display("FAIL: magnitude field empty near source"); $finish; end
    $display("PASS: quad -> magnitude -> s_mag produces a live field.");
    $finish;
  end
  initial begin #5000000 $display("TIMEOUT"); $finish; end
endmodule
