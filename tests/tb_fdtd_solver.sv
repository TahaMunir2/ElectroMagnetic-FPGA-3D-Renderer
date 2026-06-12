`timescale 1ns/1ps

module tb_fdtd_solver;

    localparam CELLS      = 128;
    localparam CELL_WIDTH = 7;
    localparam DATA_WIDTH = 16;
    localparam GRID       = CELLS * CELLS;

    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;

    logic signed [DATA_WIDTH-1:0] ey_mem [0:GRID-1];
    logic signed [DATA_WIDTH-1:0] ex_mem [0:GRID-1];
    logic signed [DATA_WIDTH-1:0] bz_mem [0:GRID-1];

    logic [2*CELL_WIDTH-1:0] ey_rd_addr, ey_wr_addr, ey_adj_rd_addr;
    logic [DATA_WIDTH-1:0]   ey_rd_dout, ey_wr_data, ey_adj_dout;
    logic                    ey_we;

    logic [2*CELL_WIDTH-1:0] ex_rd_addr, ex_wr_addr;
    logic [DATA_WIDTH-1:0]   ex_rd_dout, ex_wr_data;
    logic                    ex_we;

    logic [2*CELL_WIDTH-1:0] bz_rd_addr, bz_wr_addr, bz_adj_rd_addr;
    logic [DATA_WIDTH-1:0]   bz_rd_dout, bz_wr_data, bz_adj_dout;
    logic                    bz_we;

    logic solver_enable, solver_done;
    logic [DATA_WIDTH-1:0]   source_in;
    logic                    source_valid;
    logic [2*CELL_WIDTH-1:0] source_addr;

    always_ff @(posedge clk) begin
        if (ey_we) ey_mem[ey_wr_addr] <= ey_wr_data;
        if (ex_we) ex_mem[ex_wr_addr] <= ex_wr_data;
        if (bz_we) bz_mem[bz_wr_addr] <= bz_wr_data;

        ey_rd_dout  <= (ey_we && ey_rd_addr     == ey_wr_addr) ? ey_wr_data : ey_mem[ey_rd_addr];
        ey_adj_dout <= (ey_we && ey_adj_rd_addr == ey_wr_addr) ? ey_wr_data : ey_mem[ey_adj_rd_addr];
        ex_rd_dout  <= (ex_we && ex_rd_addr     == ex_wr_addr) ? ex_wr_data : ex_mem[ex_rd_addr];
        bz_rd_dout  <= (bz_we && bz_rd_addr     == bz_wr_addr) ? bz_wr_data : bz_mem[bz_rd_addr];
        bz_adj_dout <= (bz_we && bz_adj_rd_addr == bz_wr_addr) ? bz_wr_data : bz_mem[bz_adj_rd_addr];
    end

    fdtd_solver #(
        .TOTAL_ROWS(CELLS),
        .ROWS(CELLS),
        .COLUMNS(CELLS),
        .ROW_OFFSET(0),
        .FIRST_LANE(1),
        .LAST_LANE(1),
        .CELL_WIDTH(CELL_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .source_in(source_in),
        .source_valid(source_valid),
        .source_addr(source_addr),
        .ey_rd_addr(ey_rd_addr),
        .ey_rd_dout(ey_rd_dout),
        .ey_wr_addr(ey_wr_addr),
        .ey_wr_data(ey_wr_data),
        .ey_we(ey_we),
        .ex_rd_addr(ex_rd_addr),
        .ex_rd_dout(ex_rd_dout),
        .ex_wr_addr(ex_wr_addr),
        .ex_wr_data(ex_wr_data),
        .ex_we(ex_we),
        .bz_rd_addr(bz_rd_addr),
        .bz_rd_dout(bz_rd_dout),
        .bz_wr_addr(bz_wr_addr),
        .bz_wr_data(bz_wr_data),
        .bz_we(bz_we),
        .solver_enable(solver_enable),
        .solver_done(solver_done),
        .bz_adj_rd_addr(bz_adj_rd_addr),
        .bz_adj_dout(bz_adj_dout),
        .ey_adj_rd_addr(ey_adj_rd_addr),
        .ey_adj_dout(ey_adj_dout),
        .current_row(),
        .current_col(),
        .e_phase()
    );

    function automatic integer flat(input integer row, input integer col);
        flat = row * CELLS + col;
    endfunction

    task wait_done;
        input integer max_cycles;
        integer i;
        begin
            i = 0;
            while (!solver_done && i < max_cycles) begin
                @(posedge clk);
                i = i + 1;
            end
            if (!solver_done) begin
                $display("FAIL: solver_done never asserted (timeout %0d cycles)", max_cycles);
                $finish;
            end
        end
    endtask

    integer row, col;
    integer cycles_taken;
    logic signed [DATA_WIDTH-1:0] ey_val;
    logic signed [DATA_WIDTH-1:0] pml_val;
    logic signed [DATA_WIDTH-1:0] int_val;

    initial begin
        for (int i = 0; i < GRID; i++) begin
            ey_mem[i] = '0;
            ex_mem[i] = '0;
            bz_mem[i] = '0;
        end

        solver_enable = 1'b0;
        source_valid  = 1'b0;
        source_in     = '0;
        source_addr   = flat(8, 8);

        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);


        source_in     = 16'sd8192;
        source_valid  = 1'b1;
        solver_enable = 1'b1;

        cycles_taken = 0;
        @(posedge clk);
        while (!solver_done) begin
            @(posedge clk);
            cycles_taken = cycles_taken + 1;
        end
        cycles_taken = cycles_taken + 1;

        if (cycles_taken !== 2*GRID + 4) begin
            $display("test 1 failed: cycle count %0d", cycles_taken);
            $finish;
        end
        $display("test 1 passed: iteration took %0d cycles", cycles_taken);

        ey_val = ey_mem[flat(8,8)];
        if (ey_val == '0) begin
            $display("test 2 failed: ey still zero after inject");
            $finish;
        end
        $display("test 2 passed: source injected, ey = %0d", $signed(ey_val));


        for (col = 0; col < CELLS; col++) begin
            if (ey_mem[flat(0, col)] !== '0) begin
                $display("test 3 failed: top boundary not zero at col %0d", col);
                $finish;
            end
            if (ey_mem[flat(CELLS-1, col)] !== '0) begin
                $display("test 3 failed: bottom boundary not zero at col %0d", col);
                $finish;
            end
        end
        $display("test 3 passed: ey boundary rows clear");


        for (row = 0; row < CELLS; row++) begin
            if (ex_mem[flat(row, 0)] !== '0) begin
                $display("test 4 failed: left boundary not zero at row %0d", row);
                $finish;
            end
            if (ex_mem[flat(row, CELLS-1)] !== '0) begin
                $display("test 4 failed: right boundary not zero at row %0d", row);
                $finish;
            end
        end
        $display("test 4 passed: ex boundary cols clear");


        solver_enable = 1'b0;
        @(posedge clk);
        solver_enable = 1'b1;
        source_valid  = 1'b1;

        cycles_taken = 0;
        while (!solver_done && cycles_taken < 3*GRID + 10) begin
            @(posedge clk);
            cycles_taken = cycles_taken + 1;
        end
        if (!solver_done) begin
            $display("test 5 failed: done didnt refire");
            $finish;
        end
        $display("test 5 passed: done refires");


        solver_enable = 1'b1;
        repeat (100) @(posedge clk);
        rst = 1'b1;
        @(posedge clk);
        rst = 1'b0;
        repeat (5) @(posedge clk);
        solver_enable = 1'b0;
        repeat (10) @(posedge clk);
        if (ey_we || ex_we || bz_we) begin
            $display("test 6 failed: writes still active after reset");
            $finish;
        end
        $display("test 6 passed: reset halts solver");


        for (int i = 0; i < GRID; i++) begin
            ey_mem[i] = 16'sd8192;
            ex_mem[i] = '0;
            bz_mem[i] = '0;
        end

        rst = 1'b1;
        @(posedge clk);
        rst           = 1'b0;
        source_valid  = 1'b0;
        solver_enable = 1'b1;
        repeat (2) @(posedge clk);

        wait_done(3*GRID + 10);

        pml_val = ey_mem[flat(2, 96)];
        int_val = ey_mem[flat(10, 96)];

        if (int_val !== 16'sd8192) begin
            $display("test 7 failed: interior cell modified, got %0d", $signed(int_val));
            $finish;
        end
        if (int_val <= pml_val) begin
            $display("test 7 failed: pml cell not attenuated");
            $finish;
        end
        if (ey_mem[flat(0, 96)] !== '0) begin
            $display("test 7 failed: boundary row not zero after pml run");
            $finish;
        end
        $display("test 7 passed: pml attenuates, interior untouched (pml=%0d interior=%0d)", $signed(pml_val), $signed(int_val));

        $display("all 7 tests passed");
        $finish;
    end

endmodule
