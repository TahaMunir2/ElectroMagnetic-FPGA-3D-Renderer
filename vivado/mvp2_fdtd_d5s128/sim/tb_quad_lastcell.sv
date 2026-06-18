`timescale 1ns/1ps
// Bug-2 check: does every cell of each phase get written? Monitor lane-0 write
// addresses over one iteration and report the max Ey and Bz write address. With
// the bug the last 4 cells are dropped (max = GRID_SIZE-5); fixed, max = GRID_SIZE-1.
module tb_quad_lastcell;
  localparam DW=16, CW=6;
  logic clk=0; always #5 clk=~clk;
  logic rst; logic signed [DW-1:0] source_in; logic source_valid;
  logic [2*CW-1:0] source_addr; logic solver_enable; logic solver_done;
  top_fdtd_quad_lane dut(.clk(clk),.rst(rst),.source_in(source_in),.source_valid(source_valid),
    .source_addr(source_addr),.solver_enable(solver_enable),.solver_done(solver_done));
  localparam GS = 4096;   // this test core: GRID_SIZE=4096
  logic [2*CW-1:0] max_ey, max_bz;
  initial begin max_ey=0; max_bz=0; end
  always @(posedge clk) if(!rst && solver_enable) begin
    if (dut.slv_ey_we[0] && dut.slv_ey_wr_addr[0] > max_ey) max_ey = dut.slv_ey_wr_addr[0];
    if (dut.slv_bz_we[0] && dut.slv_bz_wr_addr[0] > max_bz) max_bz = dut.slv_bz_wr_addr[0];
  end
  initial begin
    rst=1; source_valid=1; source_in=16'sd3000; source_addr=8*64+32; solver_enable=0;
    max_ey=-1; max_bz=-1;
    repeat(5)@(posedge clk); rst=0; @(posedge clk);
    solver_enable=1; @(posedge solver_done);
    $display("GRID_SIZE=%0d  last cell index=%0d", GS, GS-1);
    $display("max Ey write addr = %0d   (want %0d)", max_ey, GS-1);
    $display("max Bz write addr = %0d   (want %0d)", max_bz, GS-1);
    if (max_ey==GS-1 && max_bz==GS-1) $display("PASS: last cell of each phase IS written");
    else $display("FAIL: last cells dropped (Ey short by %0d, Bz short by %0d)", GS-1-max_ey, GS-1-max_bz);
    $finish;
  end
endmodule
