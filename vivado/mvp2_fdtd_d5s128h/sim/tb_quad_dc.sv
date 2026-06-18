`timescale 1ns/1ps
// DC-bias test: drive a few source cycles, stop, free-run, and track the SIGNED
// sum of Ey writes per scan (= the field's DC component). Floor truncation
// injects a one-sided bias that accumulates (sum drifts away from 0);
// round-to-nearest keeps it ~0. Run at lossless ca to expose it.
module tb_quad_dc;
  localparam DW=16, CW=6;
  logic clk=0; always #5 clk=~clk;
  logic rst; logic signed [DW-1:0] source_in; logic source_valid;
  logic [2*CW-1:0] source_addr; logic solver_enable; logic solver_done;
  top_fdtd_quad_lane dut(.clk(clk),.rst(rst),.source_in(source_in),.source_valid(source_valid),
    .source_addr(source_addr),.solver_enable(solver_enable),.solver_done(solver_done));
  integer it; longint dcsum;
  always @(posedge clk) if(!rst) begin
    dcsum = dcsum + $signed(dut.ey_wr_data[0]) + $signed(dut.ey_wr_data[1])
                  + $signed(dut.ey_wr_data[2]) + $signed(dut.ey_wr_data[3]);
  end
  initial begin
    rst=1; source_valid=1; source_in=16'sd3000; source_addr=20*64+32; solver_enable=0;
    repeat(5)@(posedge clk); rst=0; @(posedge clk);
    for(it=1; it<=10; it=it+1) begin   // drive 10 cycles
      solver_enable=1; @(posedge solver_done); source_in <= -source_in;
      solver_enable=0; repeat(2)@(posedge clk);
    end
    source_valid=0; source_in=0;
    for(it=1; it<=200; it=it+1) begin
      solver_enable=1; dcsum=0; @(posedge solver_done);
      if (it%40==0) $display("  iter %3d after off: signed-sum(Ey) = %0d", it, dcsum);
      solver_enable=0; repeat(2)@(posedge clk);
    end
    $finish;
  end
endmodule
