// ============================================================================
//  heightmap_bram_dp128.sv  (true dual-port, read-only, 128x128 heightmap)
//  ----------------------------------------------------------------------------
//  Dual-port version of heightmap_bram for the folded marcher: two independent
//  read ports (a/b) share ONE memory array, so each instance is ONE copy of the
//  heightmap serving two of the marcher's logical ports.  4 instances cover the
//  8 shared ports per lane = 4 copies = 32 RAMB36 tiles (16384 x 16b).
//
//  Init is the SAME hyperbolic-paraboloid saddle as heightmap_bram and
//  auto-scales with ADDR_W (ADDR_W=14 -> 128x128, n=128, +/-0.5 in Q2.13).
//  Vivado infers a true dual-port RAMB36E2 from the ram_style attribute and the
//  two registered read ports.
// ============================================================================

module heightmap_bram_dp128 #(
    parameter int ADDR_W = 14,                       // 128x128
    parameter int DATA_W = 16,
    parameter bit USE_INIT_FILE = 1'b0,
    parameter string INIT_FILE = "heightmap_128x128.hex",
    parameter bit USE_MOCK_DATA = 1'b1
)(
    input  logic                       clk,
    // port A
    input  logic [ADDR_W-1:0]          addr_a,
    input  logic                       re_a,
    output logic signed [DATA_W-1:0]   dout_a,
    // port B
    input  logic [ADDR_W-1:0]          addr_b,
    input  logic                       re_b,
    output logic signed [DATA_W-1:0]   dout_b
);
    localparam int DEPTH = 1 << ADDR_W;

    (* ram_style = "block" *)
    logic signed [DATA_W-1:0] mem [0:DEPTH-1];

    initial begin
        int x, y, n, cx, cy, denom, saddle;
        if (USE_INIT_FILE) begin
            $readmemh(INIT_FILE, mem);
        end else if (USE_MOCK_DATA) begin
            n = 1 << (ADDR_W / 2);
            denom = (n / 2) * (n / 2);
            for (int addr_i = 0; addr_i < DEPTH; addr_i++) begin
                x = addr_i & (n - 1);
                y = addr_i >> (ADDR_W / 2);
                cx = x - (n / 2);
                cy = y - (n / 2);
                saddle = ((cx * cx - cy * cy) * 4096) / denom;
                mem[addr_i] = saddle;
            end
        end else begin
            for (int addr_i = 0; addr_i < DEPTH; addr_i++)
                mem[addr_i] = '0;
        end
    end

    // Two independent registered read ports (true dual-port).
    always_ff @(posedge clk) begin
        if (re_a) dout_a <= mem[addr_a];
    end
    always_ff @(posedge clk) begin
        if (re_b) dout_b <= mem[addr_b];
    end

endmodule
