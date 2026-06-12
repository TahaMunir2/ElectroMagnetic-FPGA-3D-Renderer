`timescale 1ns/1ps

module tb_top_fdtd_hex_lane;

    localparam LANES      = 16;
    localparam TOTAL_ROWS = 128;
    localparam ROWS       = 8;
    localparam COLUMNS    = 128;
    localparam GRID_SIZE  = ROWS * COLUMNS;
    localparam DATA_WIDTH = 16;
    localparam CELL_WIDTH = 7;

    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;

    logic [DATA_WIDTH-1:0]   source_in;
    logic                    source_valid;
    logic [2*CELL_WIDTH-1:0] source_addr;
    logic                    solver_enable;
    logic                    solver_done;

    top_fdtd_hex_lane #(
        .LANES(LANES),
        .TOTAL_ROWS(TOTAL_ROWS),
        .ROWS(ROWS),
        .COLUMNS(COLUMNS),
        .CELL_WIDTH(CELL_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .source_in(source_in),
        .source_valid(source_valid),
        .source_addr(source_addr),
        .solver_enable(solver_enable),
        .solver_done(solver_done)
    );

    function automatic integer lflat(input integer local_row, input integer col);
        lflat = local_row * COLUMNS + col;
    endfunction

    task automatic wait_done(input integer max_cycles);
        integer i;
        begin
            i = 0;
            @(posedge clk);
            while (!solver_done && i < max_cycles) begin
                @(posedge clk);
                i++;
            end
            if (i >= max_cycles) begin
                $display("done timeout at %0d cycles", max_cycles);
                $finish;
            end
        end
    endtask

    task automatic next_iter;
        begin
            @(negedge clk); solver_enable = 1'b0;
            @(posedge clk);
            @(negedge clk); solver_enable = 1'b1;
            wait_done(3 * GRID_SIZE);
        end
    endtask

    integer col, row, lane;
    integer cycles_taken;
    logic   nonzero_found;

    initial begin
        source_in     = '0;
        source_valid  = 1'b0;
        source_addr   = '0;
        solver_enable = 1'b0;

        repeat(5) @(posedge clk);
        rst = 1'b0;
        repeat(2) @(posedge clk);

        source_in     = 16'sd8192;
        source_valid  = 1'b1;
        source_addr   = 16 * COLUMNS + 8;
        solver_enable = 1'b1;

        cycles_taken = 0;
        @(posedge clk);
        while (!solver_done) begin
            @(posedge clk);
            cycles_taken++;
        end
        cycles_taken++;
        if (cycles_taken !== 2*GRID_SIZE + 4) begin
            $display("test 1 failed: cycle count %0d", cycles_taken);
            $finish;
        end
        $display("test 1 passed: iteration took %0d cycles", cycles_taken);

        if ($signed(dut.bram_2.ey_mem_0[lflat(0, 8)]) == 0) begin
            $display("test 2 failed: ey still zero after inject");
            $finish;
        end
        $display("test 2 passed: source injected");

        for (col = 0; col < COLUMNS; col++) begin
            if (dut.bram_0.ey_mem_0[lflat(0, col)] !== '0) begin
                $display("test 3 failed: top boundary not zero at col %0d", col);
                $finish;
            end
        end
        $display("test 3 passed: top boundary clear");

        for (col = 0; col < COLUMNS; col++) begin
            if (dut.bram_15.ey_mem_0[lflat(ROWS-1, col)] !== '0) begin
                $display("test 4 failed: bottom boundary not zero at col %0d", col);
                $finish;
            end
        end
        $display("test 4 passed: bottom boundary clear");

        for (lane = 0; lane < LANES; lane++) begin
            for (row = 0; row < ROWS; row++) begin
                case (lane)
                    0:  if (dut.bram_0.ex_mem_0[lflat(row,0)]  !== '0) begin $display("test 5 failed: left boundary not zero lane %0d row %0d", lane, row); $finish; end
                    1:  if (dut.bram_1.ex_mem_0[lflat(row,0)]  !== '0) begin $display("test 5 failed: left boundary not zero lane %0d row %0d", lane, row); $finish; end
                    2:  if (dut.bram_2.ex_mem_0[lflat(row,0)]  !== '0) begin $display("test 5 failed: left boundary not zero lane %0d row %0d", lane, row); $finish; end
                    3:  if (dut.bram_3.ex_mem_0[lflat(row,0)]  !== '0) begin $display("test 5 failed: left boundary not zero lane %0d row %0d", lane, row); $finish; end
                    4:  if (dut.bram_4.ex_mem_0[lflat(row,0)]  !== '0) begin $display("test 5 failed: left boundary not zero lane %0d row %0d", lane, row); $finish; end
                    5:  if (dut.bram_5.ex_mem_0[lflat(row,0)]  !== '0) begin $display("test 5 failed: left boundary not zero lane %0d row %0d", lane, row); $finish; end
                    6:  if (dut.bram_6.ex_mem_0[lflat(row,0)]  !== '0) begin $display("test 5 failed: left boundary not zero lane %0d row %0d", lane, row); $finish; end
                    7:  if (dut.bram_7.ex_mem_0[lflat(row,0)]  !== '0) begin $display("test 5 failed: left boundary not zero lane %0d row %0d", lane, row); $finish; end
                    8:  if (dut.bram_8.ex_mem_0[lflat(row,0)]  !== '0) begin $display("test 5 failed: left boundary not zero lane %0d row %0d", lane, row); $finish; end
                    9:  if (dut.bram_9.ex_mem_0[lflat(row,0)]  !== '0) begin $display("test 5 failed: left boundary not zero lane %0d row %0d", lane, row); $finish; end
                    10: if (dut.bram_10.ex_mem_0[lflat(row,0)] !== '0) begin $display("test 5 failed: left boundary not zero lane %0d row %0d", lane, row); $finish; end
                    11: if (dut.bram_11.ex_mem_0[lflat(row,0)] !== '0) begin $display("test 5 failed: left boundary not zero lane %0d row %0d", lane, row); $finish; end
                    12: if (dut.bram_12.ex_mem_0[lflat(row,0)] !== '0) begin $display("test 5 failed: left boundary not zero lane %0d row %0d", lane, row); $finish; end
                    13: if (dut.bram_13.ex_mem_0[lflat(row,0)] !== '0) begin $display("test 5 failed: left boundary not zero lane %0d row %0d", lane, row); $finish; end
                    14: if (dut.bram_14.ex_mem_0[lflat(row,0)] !== '0) begin $display("test 5 failed: left boundary not zero lane %0d row %0d", lane, row); $finish; end
                    15: if (dut.bram_15.ex_mem_0[lflat(row,0)] !== '0) begin $display("test 5 failed: left boundary not zero lane %0d row %0d", lane, row); $finish; end
                endcase
            end
        end

        $display("test 5 passed: left boundary clear");

        for (lane = 0; lane < LANES; lane++) begin
            for (row = 0; row < ROWS; row++) begin
                case (lane)
                    0:  if (dut.bram_0.ex_mem_0[lflat(row,COLUMNS-1)]  !== '0) begin $display("test 6 failed: right boundary not zero lane %0d row %0d", lane, row); $finish; end
                    1:  if (dut.bram_1.ex_mem_0[lflat(row,COLUMNS-1)]  !== '0) begin $display("test 6 failed: right boundary not zero lane %0d row %0d", lane, row); $finish; end
                    2:  if (dut.bram_2.ex_mem_0[lflat(row,COLUMNS-1)]  !== '0) begin $display("test 6 failed: right boundary not zero lane %0d row %0d", lane, row); $finish; end
                    3:  if (dut.bram_3.ex_mem_0[lflat(row,COLUMNS-1)]  !== '0) begin $display("test 6 failed: right boundary not zero lane %0d row %0d", lane, row); $finish; end
                    4:  if (dut.bram_4.ex_mem_0[lflat(row,COLUMNS-1)]  !== '0) begin $display("test 6 failed: right boundary not zero lane %0d row %0d", lane, row); $finish; end
                    5:  if (dut.bram_5.ex_mem_0[lflat(row,COLUMNS-1)]  !== '0) begin $display("test 6 failed: right boundary not zero lane %0d row %0d", lane, row); $finish; end
                    6:  if (dut.bram_6.ex_mem_0[lflat(row,COLUMNS-1)]  !== '0) begin $display("test 6 failed: right boundary not zero lane %0d row %0d", lane, row); $finish; end
                    7:  if (dut.bram_7.ex_mem_0[lflat(row,COLUMNS-1)]  !== '0) begin $display("test 6 failed: right boundary not zero lane %0d row %0d", lane, row); $finish; end
                    8:  if (dut.bram_8.ex_mem_0[lflat(row,COLUMNS-1)]  !== '0) begin $display("test 6 failed: right boundary not zero lane %0d row %0d", lane, row); $finish; end
                    9:  if (dut.bram_9.ex_mem_0[lflat(row,COLUMNS-1)]  !== '0) begin $display("test 6 failed: right boundary not zero lane %0d row %0d", lane, row); $finish; end
                    10: if (dut.bram_10.ex_mem_0[lflat(row,COLUMNS-1)] !== '0) begin $display("test 6 failed: right boundary not zero lane %0d row %0d", lane, row); $finish; end
                    11: if (dut.bram_11.ex_mem_0[lflat(row,COLUMNS-1)] !== '0) begin $display("test 6 failed: right boundary not zero lane %0d row %0d", lane, row); $finish; end
                    12: if (dut.bram_12.ex_mem_0[lflat(row,COLUMNS-1)] !== '0) begin $display("test 6 failed: right boundary not zero lane %0d row %0d", lane, row); $finish; end
                    13: if (dut.bram_13.ex_mem_0[lflat(row,COLUMNS-1)] !== '0) begin $display("test 6 failed: right boundary not zero lane %0d row %0d", lane, row); $finish; end
                    14: if (dut.bram_14.ex_mem_0[lflat(row,COLUMNS-1)] !== '0) begin $display("test 6 failed: right boundary not zero lane %0d row %0d", lane, row); $finish; end
                    15: if (dut.bram_15.ex_mem_0[lflat(row,COLUMNS-1)] !== '0) begin $display("test 6 failed: right boundary not zero lane %0d row %0d", lane, row); $finish; end
                endcase
            end
        end

        $display("test 6 passed: right boundary clear");

        repeat(20) next_iter;

        nonzero_found = 1'b0;
        for (col = 0; col < COLUMNS && !nonzero_found; col++)
            if (dut.bram_1.bz_mem_0[lflat(ROWS-1, col)] !== '0)
                nonzero_found = 1'b1;
        if (!nonzero_found) begin
            $display("test 7 failed: halo broken, lane 1 still zero");
            $finish;
        end
        $display("test 7 passed: wave crossed lane seam");

        @(negedge clk); solver_enable = 1'b0;
        @(posedge clk);
        @(negedge clk); solver_enable = 1'b1;

        cycles_taken = 0;
        @(posedge clk);
        while (!solver_done && cycles_taken < 3*GRID_SIZE) begin
            @(posedge clk);
            cycles_taken++;
        end
        if (!solver_done) begin
            $display("test 8 failed: done didnt refire");
            $finish;
        end
        $display("test 8 passed: done refires");

        solver_enable = 1'b1;
        repeat(100) @(posedge clk);
        rst = 1'b1;
        @(posedge clk);
        rst = 1'b0;
        repeat(5) @(posedge clk);
        solver_enable = 1'b0;
        repeat(10) @(posedge clk);
        if (solver_done) begin
            $display("test 9 failed: done still high after reset");
            $finish;
        end
        $display("test 9 passed: reset clears state");

        $display("all 9 tests passed");
        $finish;
    end

endmodule
