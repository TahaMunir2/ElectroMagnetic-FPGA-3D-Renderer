`timescale 1ns/1ps

module tdp_ram_model #(
    parameter ADDR_WIDTH = 6,
    parameter DATA_WIDTH = 16,
    parameter DEPTH = 64
)(
    input  wire                  clk,
    input  wire [ADDR_WIDTH-1:0] addra,
    input  wire                  ena,
    input  wire [0:0]            wea,
    input  wire [DATA_WIDTH-1:0] dina,
    output reg  [DATA_WIDTH-1:0] douta,
    input  wire [ADDR_WIDTH-1:0] addrb,
    input  wire                  enb,
    input  wire [0:0]            web,
    input  wire [DATA_WIDTH-1:0] dinb,
    output reg  [DATA_WIDTH-1:0] doutb
);
    integer i;
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    initial begin
        douta = {DATA_WIDTH{1'b0}};
        doutb = {DATA_WIDTH{1'b0}};
        for (i = 0; i < DEPTH; i = i + 1) begin
            mem[i] = {DATA_WIDTH{1'b0}};
        end
    end

    always @(posedge clk) begin
        if (ena) begin
            if (wea[0]) begin
                mem[addra] <= dina;
                douta <= dina;
            end else begin
                douta <= mem[addra];
            end
        end

        if (enb) begin
            if (web[0]) begin
                mem[addrb] <= dinb;
                doutb <= dinb;
            end else begin
                doutb <= mem[addrb];
            end
        end
    end
endmodule

module mvp2_pipeline_smoke_tb;
    localparam integer CELLS = 8;
    localparam integer CELL_WIDTH = 3;
    localparam integer DATA_WIDTH = 16;
    localparam integer ADDR_WIDTH = 2 * CELL_WIDTH;
    localparam integer DEPTH = CELLS * CELLS;
    localparam [ADDR_WIDTH-1:0] SOURCE_ADDR = 6'd9;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg solver_enable = 1'b0;
    reg source_valid = 1'b0;
    reg [DATA_WIDTH-1:0] source_q313 = {DATA_WIDTH{1'b0}};
    reg mag_mode = 1'b0;

    wire source_latched;
    wire [31:0] solver_checksum;
    wire solver_done;
    wire mag_busy;
    wire mag_done;

    wire [ADDR_WIDTH-1:0] solver_ey_addra;
    wire solver_ey_ena;
    wire [0:0] solver_ey_wea;
    wire [DATA_WIDTH-1:0] solver_ey_dina;
    wire [ADDR_WIDTH-1:0] solver_ey_addrb;
    wire solver_ey_enb;
    wire [0:0] solver_ey_web;
    wire [DATA_WIDTH-1:0] solver_ey_dinb;

    wire [ADDR_WIDTH-1:0] solver_ex_addra;
    wire solver_ex_ena;
    wire [0:0] solver_ex_wea;
    wire [DATA_WIDTH-1:0] solver_ex_dina;
    wire [ADDR_WIDTH-1:0] solver_ex_addrb;
    wire solver_ex_enb;
    wire [0:0] solver_ex_web;
    wire [DATA_WIDTH-1:0] solver_ex_dinb;

    wire [ADDR_WIDTH-1:0] solver_bz_addra;
    wire solver_bz_ena;
    wire [0:0] solver_bz_wea;
    wire [DATA_WIDTH-1:0] solver_bz_dina;
    wire [ADDR_WIDTH-1:0] solver_bz_addrb;
    wire solver_bz_enb;
    wire [0:0] solver_bz_web;
    wire [DATA_WIDTH-1:0] solver_bz_dinb;

    wire [ADDR_WIDTH-1:0] ey_addra;
    wire ey_ena;
    wire [0:0] ey_wea;
    wire [DATA_WIDTH-1:0] ey_dina;
    wire [DATA_WIDTH-1:0] ey_douta;
    wire [ADDR_WIDTH-1:0] ey_addrb;
    wire ey_enb;
    wire [0:0] ey_web;
    wire [DATA_WIDTH-1:0] ey_dinb;
    wire [DATA_WIDTH-1:0] ey_doutb;

    wire [ADDR_WIDTH-1:0] ex_addra;
    wire ex_ena;
    wire [0:0] ex_wea;
    wire [DATA_WIDTH-1:0] ex_dina;
    wire [DATA_WIDTH-1:0] ex_douta;
    wire [ADDR_WIDTH-1:0] ex_addrb;
    wire ex_enb;
    wire [0:0] ex_web;
    wire [DATA_WIDTH-1:0] ex_dinb;
    wire [DATA_WIDTH-1:0] ex_doutb;

    wire [ADDR_WIDTH-1:0] bz_addra;
    wire bz_ena;
    wire [0:0] bz_wea;
    wire [DATA_WIDTH-1:0] bz_dina;
    wire [DATA_WIDTH-1:0] bz_douta;
    wire [ADDR_WIDTH-1:0] bz_addrb;
    wire bz_enb;
    wire [0:0] bz_web;
    wire [DATA_WIDTH-1:0] bz_dinb;
    wire [DATA_WIDTH-1:0] bz_doutb;

    wire [ADDR_WIDTH-1:0] s_mag_addra;
    wire s_mag_ena;
    wire [0:0] s_mag_wea;
    wire [DATA_WIDTH-1:0] s_mag_dina;
    wire [ADDR_WIDTH-1:0] s_mag_addrb;
    wire s_mag_enb;
    wire [0:0] s_mag_web;
    wire [DATA_WIDTH-1:0] s_mag_dinb;
    wire [DATA_WIDTH-1:0] s_mag_doutb;

    wire heightmap_we;
    wire [11:0] heightmap_waddr;
    wire [DATA_WIDTH-1:0] heightmap_wdata;
    wire bridge_busy;
    wire bridge_done;
    wire bridge_ready;

    integer cycles;
    integer heightmap_writes;
    reg [DATA_WIDTH-1:0] first_heightmap_data;
    reg [11:0] first_heightmap_addr;

    always #5 clk = ~clk;

    fdtd_solver_bd_adapter #(
        .CELLS(CELLS),
        .CELL_WIDTH(CELL_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .SOURCE_ADDR(SOURCE_ADDR)
    ) u_solver_adapter (
        .clk(clk),
        .rst(rst),
        .solver_enable(solver_enable),
        .source_q313(source_q313),
        .source_valid(source_valid),
        .source_latched(source_latched),
        .solver_checksum(solver_checksum),
        .solver_done(solver_done),
        .ey_addra(solver_ey_addra),
        .ey_ena(solver_ey_ena),
        .ey_wea(solver_ey_wea),
        .ey_dina(solver_ey_dina),
        .ey_douta(ey_douta),
        .ey_addrb(solver_ey_addrb),
        .ey_enb(solver_ey_enb),
        .ey_web(solver_ey_web),
        .ey_dinb(solver_ey_dinb),
        .ey_doutb(ey_doutb),
        .ex_addra(solver_ex_addra),
        .ex_ena(solver_ex_ena),
        .ex_wea(solver_ex_wea),
        .ex_dina(solver_ex_dina),
        .ex_douta(ex_douta),
        .ex_addrb(solver_ex_addrb),
        .ex_enb(solver_ex_enb),
        .ex_web(solver_ex_web),
        .ex_dinb(solver_ex_dinb),
        .bz_addra(solver_bz_addra),
        .bz_ena(solver_bz_ena),
        .bz_wea(solver_bz_wea),
        .bz_dina(solver_bz_dina),
        .bz_douta(bz_douta),
        .bz_addrb(solver_bz_addrb),
        .bz_enb(solver_bz_enb),
        .bz_web(solver_bz_web),
        .bz_dinb(solver_bz_dinb),
        .bz_doutb(bz_doutb)
    );

    field_magnitude_bd_adapter #(
        .CELLS(CELLS),
        .CELL_WIDTH(CELL_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_mag_adapter (
        .clk(clk),
        .rst(rst),
        .start(solver_done),
        .mag_mode(mag_mode),
        .busy(mag_busy),
        .done(mag_done),
        .solver_ey_addra(solver_ey_addra),
        .solver_ey_ena(solver_ey_ena),
        .solver_ey_wea(solver_ey_wea),
        .solver_ey_dina(solver_ey_dina),
        .solver_ey_addrb(solver_ey_addrb),
        .solver_ey_enb(solver_ey_enb),
        .solver_ey_web(solver_ey_web),
        .solver_ey_dinb(solver_ey_dinb),
        .solver_ex_addra(solver_ex_addra),
        .solver_ex_ena(solver_ex_ena),
        .solver_ex_wea(solver_ex_wea),
        .solver_ex_dina(solver_ex_dina),
        .solver_ex_addrb(solver_ex_addrb),
        .solver_ex_enb(solver_ex_enb),
        .solver_ex_web(solver_ex_web),
        .solver_ex_dinb(solver_ex_dinb),
        .solver_bz_addra(solver_bz_addra),
        .solver_bz_ena(solver_bz_ena),
        .solver_bz_wea(solver_bz_wea),
        .solver_bz_dina(solver_bz_dina),
        .solver_bz_addrb(solver_bz_addrb),
        .solver_bz_enb(solver_bz_enb),
        .solver_bz_web(solver_bz_web),
        .solver_bz_dinb(solver_bz_dinb),
        .ey_addra(ey_addra),
        .ey_ena(ey_ena),
        .ey_wea(ey_wea),
        .ey_dina(ey_dina),
        .ey_douta(ey_douta),
        .ey_addrb(ey_addrb),
        .ey_enb(ey_enb),
        .ey_web(ey_web),
        .ey_dinb(ey_dinb),
        .ex_addra(ex_addra),
        .ex_ena(ex_ena),
        .ex_wea(ex_wea),
        .ex_dina(ex_dina),
        .ex_douta(ex_douta),
        .ex_addrb(ex_addrb),
        .ex_enb(ex_enb),
        .ex_web(ex_web),
        .ex_dinb(ex_dinb),
        .bz_addra(bz_addra),
        .bz_ena(bz_ena),
        .bz_wea(bz_wea),
        .bz_dina(bz_dina),
        .bz_douta(bz_douta),
        .bz_addrb(bz_addrb),
        .bz_enb(bz_enb),
        .bz_web(bz_web),
        .bz_dinb(bz_dinb),
        .s_mag_addra(s_mag_addra),
        .s_mag_ena(s_mag_ena),
        .s_mag_wea(s_mag_wea),
        .s_mag_dina(s_mag_dina)
    );

    tdp_ram_model #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .DEPTH(DEPTH)) ey_ram (
        .clk(clk), .addra(ey_addra), .ena(ey_ena), .wea(ey_wea), .dina(ey_dina), .douta(ey_douta),
        .addrb(ey_addrb), .enb(ey_enb), .web(ey_web), .dinb(ey_dinb), .doutb(ey_doutb)
    );

    tdp_ram_model #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .DEPTH(DEPTH)) ex_ram (
        .clk(clk), .addra(ex_addra), .ena(ex_ena), .wea(ex_wea), .dina(ex_dina), .douta(ex_douta),
        .addrb(ex_addrb), .enb(ex_enb), .web(ex_web), .dinb(ex_dinb), .doutb(ex_doutb)
    );

    tdp_ram_model #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .DEPTH(DEPTH)) bz_ram (
        .clk(clk), .addra(bz_addra), .ena(bz_ena), .wea(bz_wea), .dina(bz_dina), .douta(bz_douta),
        .addrb(bz_addrb), .enb(bz_enb), .web(bz_web), .dinb(bz_dinb), .doutb(bz_doutb)
    );

    tdp_ram_model #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .DEPTH(DEPTH)) s_mag_ram (
        .clk(clk), .addra(s_mag_addra), .ena(s_mag_ena), .wea(s_mag_wea), .dina(s_mag_dina), .douta(),
        .addrb(s_mag_addrb), .enb(s_mag_enb), .web(s_mag_web), .dinb(s_mag_dinb), .doutb(s_mag_doutb)
    );

    s_mag_to_renderer_bridge #(
        .SRC_CELLS(CELLS),
        .DST_CELLS(2),
        .SRC_ADDR_WIDTH(ADDR_WIDTH),
        .DST_ADDR_WIDTH(12),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_bridge (
        .clk(clk),
        .rst(rst),
        .start(mag_done),
        .s_mag_addr(s_mag_addrb),
        .s_mag_en(s_mag_enb),
        .s_mag_we(s_mag_web),
        .s_mag_din(s_mag_dinb),
        .s_mag_dout(s_mag_doutb),
        .heightmap_we(heightmap_we),
        .heightmap_waddr(heightmap_waddr),
        .heightmap_wdata(heightmap_wdata),
        .busy(bridge_busy),
        .done(bridge_done),
        .ready(bridge_ready)
    );

    always @(posedge clk) begin
        if (rst) begin
            heightmap_writes <= 0;
            first_heightmap_data <= {DATA_WIDTH{1'b0}};
            first_heightmap_addr <= 12'd0;
        end else if (heightmap_we) begin
            if (heightmap_writes == 0) begin
                first_heightmap_data <= heightmap_wdata;
                first_heightmap_addr <= heightmap_waddr;
            end
            heightmap_writes <= heightmap_writes + 1;
        end
    end

    initial begin
        repeat (5) @(negedge clk);
        rst = 1'b0;
        mag_mode = 1'b0;

        @(negedge clk);
        source_q313 = 16'sd4096;
        source_valid = 1'b1;

        @(negedge clk);
        source_valid = 1'b0;
        solver_enable = 1'b1;

        repeat (3) @(posedge clk);
        if (!source_latched) begin
            $display("FAIL: source was not latched");
            $finish(1);
        end

        for (cycles = 0; cycles < 1000 && !solver_done; cycles = cycles + 1) begin
            @(posedge clk);
        end
        if (!solver_done) begin
            $display("FAIL: solver_done timeout");
            $finish(1);
        end
        $display("INFO: solver_done after %0d cycles, checksum=0x%08x", cycles, solver_checksum);

        for (cycles = 0; cycles < 1000 && !mag_done; cycles = cycles + 1) begin
            @(posedge clk);
        end
        if (!mag_done) begin
            $display("FAIL: mag_done timeout");
            $finish(1);
        end
        $display("INFO: mag_done after %0d cycles, s_mag[%0d]=0x%04x", cycles, SOURCE_ADDR, s_mag_ram.mem[SOURCE_ADDR]);

        for (cycles = 0; cycles < 200 && !bridge_done; cycles = cycles + 1) begin
            @(posedge clk);
        end
        if (!bridge_done) begin
            $display("FAIL: renderer bridge timeout");
            $finish(1);
        end
        @(posedge clk);

        if (solver_checksum == 32'd0) begin
            $display("FAIL: solver checksum stayed zero");
            $finish(1);
        end
        if (s_mag_ram.mem[SOURCE_ADDR] == 16'd0) begin
            $display("FAIL: magnitude memory did not receive nonzero source-cell data");
            $finish(1);
        end
        if (heightmap_writes != 4) begin
            $display("FAIL: expected 4 heightmap writes, got %0d", heightmap_writes);
            $finish(1);
        end
        if (first_heightmap_addr != 12'd0) begin
            $display("FAIL: first heightmap write address was %0d", first_heightmap_addr);
            $finish(1);
        end
        if (first_heightmap_data != s_mag_ram.mem[SOURCE_ADDR]) begin
            $display("FAIL: bridge first sample mismatch, got 0x%04x expected 0x%04x",
                first_heightmap_data, s_mag_ram.mem[SOURCE_ADDR]);
            $finish(1);
        end

        $display("PASS: solver -> |E| magnitude -> s_mag_bram -> renderer bridge smoke test passed");
        $display("INFO: first heightmap sample=0x%04x writes=%0d bridge_ready=%0b",
            first_heightmap_data, heightmap_writes, bridge_ready);
        $finish;
    end
endmodule
