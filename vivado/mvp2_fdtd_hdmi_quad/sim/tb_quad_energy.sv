`timescale 1ns/1ps
module tb_quad_energy;
  localparam DW=16, CW=6;
  logic clk=0; always #5 clk=~clk;
  logic rst; logic signed [DW-1:0] source_in; logic source_valid;
  logic [2*CW-1:0] source_addr; logic solver_enable; logic solver_done;
  top_fdtd_quad_lane dut(.clk(clk),.rst(rst),.source_in(source_in),.source_valid(source_valid),
    .source_addr(source_addr),.solver_enable(solver_enable),.solver_done(solver_done));
  integer it, peak, i, j;
  function int absv(input signed [DW-1:0] v); absv = v[DW-1]? -v : v; endfunction
  // peak |Ey| written across all 4 lanes each iteration
  always @(posedge clk) if(!rst) begin
    if (absv(dut.ey_wr_data[0])>peak) peak=absv(dut.ey_wr_data[0]);
    if (absv(dut.ey_wr_data[1])>peak) peak=absv(dut.ey_wr_data[1]);
    if (absv(dut.ey_wr_data[2])>peak) peak=absv(dut.ey_wr_data[2]);
    if (absv(dut.ey_wr_data[3])>peak) peak=absv(dut.ey_wr_data[3]);
  end
  initial begin
    rst=1; source_valid=1; source_in=16'sd2000; source_addr=12'd2080; solver_enable=0; peak=0;
    repeat(5)@(posedge clk); rst=0; @(posedge clk);
    for(it=1; it<=40; it=it+1) begin
      solver_enable=1;
      @(posedge solver_done);
      source_in <= -source_in;                 // AC drive, coherent
      if (it%20==0) $display("iter %0d  peak|Ey| = %0d  (%.3f, sat@32767)", it, peak, peak/8192.0);
      peak=0;
      solver_enable=0; repeat(2)@(posedge clk);  // restart pulse
    end
    $finish;
  end
endmodule
