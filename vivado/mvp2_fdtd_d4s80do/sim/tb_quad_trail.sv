`timescale 1ns/1ps
// Moving-source TRAIL test. Sine source, dwell ~6 iters/cell, dragged across a
// row, then cut off. Metric = total sum|Ey| written per scan (cavity energy).
// After the source is off, propagating waves exit via the PML; a FROZEN
// electrostatic trail does NOT -> energy floors. Compare direct injection vs
// DC-free first-difference injection (+define DERIV).
module tb_quad_trail;
  localparam DW=16, CW=6;
  logic clk=0; always #5 clk=~clk;
  logic rst; logic signed [DW-1:0] source_in; logic source_valid;
  logic [2*CW-1:0] source_addr; logic solver_enable; logic solver_done;
  top_fdtd_quad_lane dut(.clk(clk),.rst(rst),.source_in(source_in),.source_valid(source_valid),
    .source_addr(source_addr),.solver_enable(solver_enable),.solver_done(solver_done));
  integer it, col, ph; real ssum; real e0;
  real PI; real samp, sprev;
  function automatic int absv(input signed [DW-1:0] v); absv = v[DW-1]? -v : v; endfunction
  always @(posedge clk) if(!rst) begin
    ssum = ssum + absv(dut.ey_wr_data[0]) + absv(dut.ey_wr_data[1])
                + absv(dut.ey_wr_data[2]) + absv(dut.ey_wr_data[3]);
  end
  // build the per-iteration source sample (sine, period ~28 iters)
  task automatic step_src;
    begin
      samp = 2000.0 * $sin(2.0*3.14159265*ph/28.0);
`ifdef DERIV
      source_in = $rtoi(samp - sprev);   // DC-free first difference
`else
      source_in = $rtoi(samp);           // direct
`endif
      sprev = samp; ph = ph + 1;
    end
  endtask
  initial begin
    rst=1; source_valid=1; ph=0; sprev=0.0; samp=0.0; source_in=0;
    col=8; source_addr=32*64+col; solver_enable=0;
    repeat(5)@(posedge clk); rst=0; @(posedge clk);
    // drag source across row 32, dwell 6 iters/cell, for 36 cells
    for(it=1; it<=216; it=it+1) begin
      solver_enable=1; ssum=0.0; @(posedge solver_done);
      step_src();
      if (it%6==0) begin col=col+1; source_addr <= 32*64+col; end
      solver_enable=0; repeat(2)@(posedge clk);
    end
    source_valid=0; source_in=0;
    $display("--- source OFF, watching cavity energy sum|Ey| ---");
    for(it=0; it<=180; it=it+1) begin
      solver_enable=1; ssum=0.0; @(posedge solver_done);
      if (it==0) e0=ssum;
      if (it%30==0) $display("  +%3d after off: sum|Ey|=%10.0f  (%.1f%% of initial)",
                             it, ssum, e0>0? 100.0*ssum/e0 : 0.0);
      solver_enable=0; repeat(2)@(posedge clk);
    end
    $finish;
  end
endmodule
