`timescale 1ns/1ps
module tb_quad_smoke;
  localparam DW=16, CW=6;
  logic clk=0; always #5 clk=~clk;
  logic rst; logic [DW-1:0] source_in; logic source_valid;
  logic [2*CW-1:0] source_addr; logic solver_enable; logic solver_done;
  top_fdtd_quad_lane dut(.clk(clk),.rst(rst),.source_in(source_in),.source_valid(source_valid),
    .source_addr(source_addr),.solver_enable(solver_enable),.solver_done(solver_done));
  integer i;
  initial begin
    rst=1; source_in=16'sd3000; source_valid=1; source_addr=12'd2080; solver_enable=0;
    repeat(5) @(posedge clk); rst=0; @(posedge clk);
    solver_enable=1;
    for (i=0;i<6000;i=i+1) begin
      @(posedge clk);
      if (i%256==0) begin $display("cyc %0d done=%b", i, solver_done); $fflush; end
      if (solver_done) begin $display(">>> solver_done at cyc %0d", i); $fflush; #1 $finish; end
    end
    $display("no solver_done in 6000 cyc"); $finish;
  end
endmodule
