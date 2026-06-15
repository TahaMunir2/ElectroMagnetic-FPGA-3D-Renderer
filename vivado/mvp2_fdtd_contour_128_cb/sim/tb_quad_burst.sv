`timescale 1ns/1ps
// Overflow-wrap test: drive a moving source and watch for Q3.13 wraparound in
// the Ey writes (a value near +full-scale followed by a large-negative write =
// two's-complement wrap = the "sudden explosion"). Sweeps source gain.
module tb_quad_burst;
  localparam DW=16, CW=6;
  logic clk=0; always #5 clk=~clk;
  logic rst; logic signed [DW-1:0] source_in; logic source_valid;
  logic [2*CW-1:0] source_addr; logic solver_enable; logic solver_done;
  top_fdtd_quad_lane dut(.clk(clk),.rst(rst),.source_in(source_in),.source_valid(source_valid),
    .source_addr(source_addr),.solver_enable(solver_enable),.solver_done(solver_done));
  integer it, col, ph, wraps, peak; real samp, sprev;
  integer GAIN;
  function automatic int absv(input signed [DW-1:0] v); absv = v[DW-1]? -v : v; endfunction
  // detect wrap: this write is large-negative while the previous write to the
  // same lane was large-positive (or vice-versa) -> sign flip at near-full-scale
  logic signed [DW-1:0] prevw [0:3];
  always @(posedge clk) if(!rst) begin
    for (int k=0;k<4;k++) begin
      if (absv(dut.ey_wr_data[k])>peak) peak=absv(dut.ey_wr_data[k]);
      if ( (prevw[k] >  16'sd28000 && dut.ey_wr_data[k] < -16'sd20000) ||
           (prevw[k] < -16'sd28000 && dut.ey_wr_data[k] >  16'sd20000) ) wraps=wraps+1;
      prevw[k] <= dut.ey_wr_data[k];
    end
  end
  initial begin
    for (GAIN=4; GAIN<=12; GAIN=GAIN+4) begin
      rst=1; source_valid=1; ph=0; sprev=0.0; source_in=0; col=8;
      source_addr=32*64+col; solver_enable=0; wraps=0; peak=0;
      repeat(5)@(posedge clk); rst=0; @(posedge clk);
      for(it=1; it<=400; it=it+1) begin
        solver_enable=1; @(posedge solver_done);
        samp = 2000.0*$sin(2.0*3.14159265*ph/28.0);
        source_in = $rtoi((samp - sprev)*GAIN);   // DC-free diff x GAIN
        sprev = samp; ph = ph + 1;
        if (it%6==0) begin col=(col<54)?col+1:8; source_addr <= 32*64+col; end
        solver_enable=0; repeat(2)@(posedge clk);
      end
      $display("source diff-gain x%0d : peak|Ey|=%6d (rail=32767)  wrap events=%0d",
               GAIN, peak, wraps);
    end
    $finish;
  end
endmodule
