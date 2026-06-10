// heightmap_bram_sim.sv
// Self-contained simulation model of the project's heightmap_bram for the
// model of the projects heightmap_bram for the testbench. Contract: single port,
// 1-cycle synchronous read, dout <= mem[addr] when re is high.
// On hardware you instantiate YOUR existing heightmap_bram instead.

module heightmap_bram #(
    parameter int ADDR_W = 12,
    parameter int DATA_W = 16,
    parameter     INIT_FILE = "heightmap.hex"
)(
    input  logic                     clk,
    input  logic [ADDR_W-1:0]        addr,
    input  logic                     re,
    output logic signed [DATA_W-1:0] dout
);
    logic signed [DATA_W-1:0] mem [(1<<ADDR_W)-1:0];

    initial begin
        $readmemh(INIT_FILE, mem);
    end

    always_ff @(posedge clk) begin
        if (re) dout <= mem[addr];
    end
endmodule
