`timescale 1ns/1ps

module tb_top_fdtd_quad_lane;

    localparam TOTAL_ROWS = 64;
    localparam ROWS       = 16;
    localparam COLUMNS    = 64;
    localparam GRID_SIZE  = ROWS * COLUMNS;
    localparam DATA_WIDTH = 16;
    localparam CELL_WIDTH = 6;

    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;

    logic [DATA_WIDTH-1:0]   source_in;
    logic                    source_valid;
    logic [2*CELL_WIDTH-1:0] source_addr;
    logic                    solver_enable;
    logic                    solver_done;

    top_fdtd_quad_lane #(
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

    integer col, row;
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
        source_addr   = 8 * COLUMNS + 8;
        solver_enable = 1'b1;

        cycles_taken = 0;
        @(posedge clk);
        while (!solver_done) begin
            @(posedge clk);
            cycles_taken++;
        end
        cycles_taken++;
        if (cycles_taken !== 2*GRID_SIZE) begin
            $display("wrong cycle count: %0d", cycles_taken);
            $finish;
        end

        if ($signed(dut.bram_0.ey_mem_0[lflat(8, 8)]) == 0) begin
            $display("ey still zero after inject");
            $finish;
        end

        for (col = 0; col < COLUMNS; col++) begin
            if (dut.bram_0.ey_mem_0[lflat(0, col)] !== '0) begin
                $display("top boundary not zero at col %0d", col);
                $finish;
            end
        end

        for (col = 0; col < COLUMNS; col++) begin
            if (dut.bram_3.ey_mem_0[lflat(ROWS-1, col)] !== '0) begin
                $display("bottom boundary not zero at col %0d", col);
                $finish;
            end
        end

        for (row = 0; row < ROWS; row++) begin
            if (dut.bram_0.ex_mem_0[lflat(row, 0)] !== '0 ||
                dut.bram_1.ex_mem_0[lflat(row, 0)] !== '0 ||
                dut.bram_2.ex_mem_0[lflat(row, 0)] !== '0 ||
                dut.bram_3.ex_mem_0[lflat(row, 0)] !== '0) begin
                $display("left boundary not zero at row %0d", row);
                $finish;
            end
        end

        for (row = 0; row < ROWS; row++) begin
            if (dut.bram_0.ex_mem_0[lflat(row, COLUMNS-1)] !== '0 ||
                dut.bram_1.ex_mem_0[lflat(row, COLUMNS-1)] !== '0 ||
                dut.bram_2.ex_mem_0[lflat(row, COLUMNS-1)] !== '0 ||
                dut.bram_3.ex_mem_0[lflat(row, COLUMNS-1)] !== '0) begin
                $display("right boundary not zero at row %0d", row);
                $finish;
            end
        end

        repeat(20) next_iter;

        nonzero_found = 1'b0;
        for (row = 0; row < ROWS && !nonzero_found; row++)
            for (col = 0; col < COLUMNS && !nonzero_found; col++)
                if (dut.bram_1.ey_mem_0[lflat(row, col)] !== '0)
                    nonzero_found = 1'b1;
        if (!nonzero_found) begin
            $display("halo broken, lane 1 still zero");
            $finish;
        end

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
            $display("done didnt refire");
            $finish;
        end

        solver_enable = 1'b1;
        repeat(100) @(posedge clk);
        rst = 1'b1;
        @(posedge clk);
        rst = 1'b0;
        repeat(5) @(posedge clk);
        solver_enable = 1'b0;
        repeat(10) @(posedge clk);
        if (solver_done) begin
            $display("done still high after reset");
            $finish;
        end

        $display("ok");
        $finish;
    end

endmodule
