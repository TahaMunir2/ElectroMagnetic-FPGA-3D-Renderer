`timescale 1ns/1ps

module tb_top_fdtd_hex_lane;

    localparam LANES      = 16;
    localparam TOTAL_ROWS = 128;
    localparam ROWS       = 8;
    localparam COLUMNS    = 128;
    localparam GRID_SIZE  = ROWS * COLUMNS;   // 1024 per lane
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
                $display("  FAIL: solver_done timeout after %0d cycles", max_cycles);
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

        // ─────────────────────────────────────────────────────
        // TEST 1: solver_done fires after exactly 2*GRID_SIZE cycles
        // ─────────────────────────────────────────────────────
        $display("TEST 1: solver_done timing (expect %0d cycles)", 2*GRID_SIZE);
        source_in     = 16'sd8192;
        source_valid  = 1'b1;
        source_addr   = 8 * COLUMNS + 8;   // global (8,8) → lane 1 local (0,8)
        solver_enable = 1'b1;

        cycles_taken = 0;
        @(posedge clk);
        while (!solver_done) begin
            @(posedge clk);
            cycles_taken++;
        end
        cycles_taken++;
        $display("  solver_done after %0d cycles", cycles_taken);
        if (cycles_taken !== 2*GRID_SIZE) begin
            $display("  FAIL");
            $finish;
        end
        $display("  PASS");

        // ─────────────────────────────────────────────────────
        // TEST 2: Source injection — Ey at lane 1 local (0,8) must be nonzero
        // global (8,8) → source_lane=1, local_addr=8 → lflat(0,8)
        // ─────────────────────────────────────────────────────
        $display("TEST 2: Source injection Ey(global 8,8) nonzero");
        if ($signed(dut.bram_1.ey_mem_0[lflat(0, 8)]) == 0) begin
            $display("  FAIL: Ey[global 8][8] = 0 after source injection");
            $finish;
        end
        $display("  Ey[global 8][8] = %0d  PASS",
                 $signed(dut.bram_1.ey_mem_0[lflat(0, 8)]));

        // ─────────────────────────────────────────────────────
        // TEST 3: Ey top boundary zero — global row 0 (lane 0 local row 0)
        // ─────────────────────────────────────────────────────
        $display("TEST 3: Ey top boundary (global row 0) forced zero");
        for (col = 0; col < COLUMNS; col++) begin
            if (dut.bram_0.ey_mem_0[lflat(0, col)] !== '0) begin
                $display("  FAIL: Ey[0][%0d] = %0d", col,
                         $signed(dut.bram_0.ey_mem_0[lflat(0, col)]));
                $finish;
            end
        end
        $display("  PASS");

        // ─────────────────────────────────────────────────────
        // TEST 4: Ey bottom boundary zero — global row 127 (lane 15 local row 7)
        // ─────────────────────────────────────────────────────
        $display("TEST 4: Ey bottom boundary (global row 127) forced zero");
        for (col = 0; col < COLUMNS; col++) begin
            if (dut.bram_15.ey_mem_0[lflat(ROWS-1, col)] !== '0) begin
                $display("  FAIL: Ey[127][%0d] = %0d", col,
                         $signed(dut.bram_15.ey_mem_0[lflat(ROWS-1, col)]));
                $finish;
            end
        end
        $display("  PASS");

        // ─────────────────────────────────────────────────────
        // TEST 5: Ex left boundary zero — col 0 across all lanes
        // ─────────────────────────────────────────────────────
        $display("TEST 5: Ex left boundary (col 0) forced zero");
        for (lane = 0; lane < LANES; lane++) begin
            for (row = 0; row < ROWS; row++) begin
                case (lane)
                    0:  if (dut.bram_0.ex_mem_0[lflat(row,0)]  !== '0) begin
                            $display("  FAIL: Ex[lane %0d][%0d][0] nonzero", lane, row);
                            $finish;
                        end
                    1:  if (dut.bram_1.ex_mem_0[lflat(row,0)]  !== '0) begin
                            $display("  FAIL: Ex[lane %0d][%0d][0] nonzero", lane, row);
                            $finish;
                        end
                    2:  if (dut.bram_2.ex_mem_0[lflat(row,0)]  !== '0) begin
                            $display("  FAIL: Ex[lane %0d][%0d][0] nonzero", lane, row);
                            $finish;
                        end
                    3:  if (dut.bram_3.ex_mem_0[lflat(row,0)]  !== '0) begin
                            $display("  FAIL: Ex[lane %0d][%0d][0] nonzero", lane, row);
                            $finish;
                        end
                    4:  if (dut.bram_4.ex_mem_0[lflat(row,0)]  !== '0) begin
                            $display("  FAIL: Ex[lane %0d][%0d][0] nonzero", lane, row);
                            $finish;
                        end
                    5:  if (dut.bram_5.ex_mem_0[lflat(row,0)]  !== '0) begin
                            $display("  FAIL: Ex[lane %0d][%0d][0] nonzero", lane, row);
                            $finish;
                        end
                    6:  if (dut.bram_6.ex_mem_0[lflat(row,0)]  !== '0) begin
                            $display("  FAIL: Ex[lane %0d][%0d][0] nonzero", lane, row);
                            $finish;
                        end
                    7:  if (dut.bram_7.ex_mem_0[lflat(row,0)]  !== '0) begin
                            $display("  FAIL: Ex[lane %0d][%0d][0] nonzero", lane, row);
                            $finish;
                        end
                    8:  if (dut.bram_8.ex_mem_0[lflat(row,0)]  !== '0) begin
                            $display("  FAIL: Ex[lane %0d][%0d][0] nonzero", lane, row);
                            $finish;
                        end
                    9:  if (dut.bram_9.ex_mem_0[lflat(row,0)]  !== '0) begin
                            $display("  FAIL: Ex[lane %0d][%0d][0] nonzero", lane, row);
                            $finish;
                        end
                    10: if (dut.bram_10.ex_mem_0[lflat(row,0)] !== '0) begin
                            $display("  FAIL: Ex[lane %0d][%0d][0] nonzero", lane, row);
                            $finish;
                        end
                    11: if (dut.bram_11.ex_mem_0[lflat(row,0)] !== '0) begin
                            $display("  FAIL: Ex[lane %0d][%0d][0] nonzero", lane, row);
                            $finish;
                        end
                    12: if (dut.bram_12.ex_mem_0[lflat(row,0)] !== '0) begin
                            $display("  FAIL: Ex[lane %0d][%0d][0] nonzero", lane, row);
                            $finish;
                        end
                    13: if (dut.bram_13.ex_mem_0[lflat(row,0)] !== '0) begin
                            $display("  FAIL: Ex[lane %0d][%0d][0] nonzero", lane, row);
                            $finish;
                        end
                    14: if (dut.bram_14.ex_mem_0[lflat(row,0)] !== '0) begin
                            $display("  FAIL: Ex[lane %0d][%0d][0] nonzero", lane, row);
                            $finish;
                        end
                    15: if (dut.bram_15.ex_mem_0[lflat(row,0)] !== '0) begin
                            $display("  FAIL: Ex[lane %0d][%0d][0] nonzero", lane, row);
                            $finish;
                        end
                endcase
            end
        end
        $display("  PASS");

        // ─────────────────────────────────────────────────────
        // TEST 6: Ex right boundary zero — col 127 across all lanes
        // ─────────────────────────────────────────────────────
        $display("TEST 6: Ex right boundary (col 127) forced zero");
        for (lane = 0; lane < LANES; lane++) begin
            for (row = 0; row < ROWS; row++) begin
                case (lane)
                    0:  if (dut.bram_0.ex_mem_0[lflat(row,COLUMNS-1)]  !== '0) begin
                            $display("  FAIL: Ex[lane %0d][%0d][127] nonzero", lane, row);
                            $finish;
                        end
                    1:  if (dut.bram_1.ex_mem_0[lflat(row,COLUMNS-1)]  !== '0) begin
                            $display("  FAIL: Ex[lane %0d][%0d][127] nonzero", lane, row);
                            $finish;
                        end
                    2:  if (dut.bram_2.ex_mem_0[lflat(row,COLUMNS-1)]  !== '0) begin
                            $display("  FAIL: Ex[lane %0d][%0d][127] nonzero", lane, row);
                            $finish;
                        end
                    3:  if (dut.bram_3.ex_mem_0[lflat(row,COLUMNS-1)]  !== '0) begin
                            $display("  FAIL: Ex[lane %0d][%0d][127] nonzero", lane, row);
                            $finish;
                        end
                    4:  if (dut.bram_4.ex_mem_0[lflat(row,COLUMNS-1)]  !== '0) begin
                            $display("  FAIL: Ex[lane %0d][%0d][127] nonzero", lane, row);
                            $finish;
                        end
                    5:  if (dut.bram_5.ex_mem_0[lflat(row,COLUMNS-1)]  !== '0) begin
                            $display("  FAIL: Ex[lane %0d][%0d][127] nonzero", lane, row);
                            $finish;
                        end
                    6:  if (dut.bram_6.ex_mem_0[lflat(row,COLUMNS-1)]  !== '0) begin
                            $display("  FAIL: Ex[lane %0d][%0d][127] nonzero", lane, row);
                            $finish;
                        end
                    7:  if (dut.bram_7.ex_mem_0[lflat(row,COLUMNS-1)]  !== '0) begin
                            $display("  FAIL: Ex[lane %0d][%0d][127] nonzero", lane, row);
                            $finish;
                        end
                    8:  if (dut.bram_8.ex_mem_0[lflat(row,COLUMNS-1)]  !== '0) begin
                            $display("  FAIL: Ex[lane %0d][%0d][127] nonzero", lane, row);
                            $finish;
                        end
                    9:  if (dut.bram_9.ex_mem_0[lflat(row,COLUMNS-1)]  !== '0) begin
                            $display("  FAIL: Ex[lane %0d][%0d][127] nonzero", lane, row);
                            $finish;
                        end
                    10: if (dut.bram_10.ex_mem_0[lflat(row,COLUMNS-1)] !== '0) begin
                            $display("  FAIL: Ex[lane %0d][%0d][127] nonzero", lane, row);
                            $finish;
                        end
                    11: if (dut.bram_11.ex_mem_0[lflat(row,COLUMNS-1)] !== '0) begin
                            $display("  FAIL: Ex[lane %0d][%0d][127] nonzero", lane, row);
                            $finish;
                        end
                    12: if (dut.bram_12.ex_mem_0[lflat(row,COLUMNS-1)] !== '0) begin
                            $display("  FAIL: Ex[lane %0d][%0d][127] nonzero", lane, row);
                            $finish;
                        end
                    13: if (dut.bram_13.ex_mem_0[lflat(row,COLUMNS-1)] !== '0) begin
                            $display("  FAIL: Ex[lane %0d][%0d][127] nonzero", lane, row);
                            $finish;
                        end
                    14: if (dut.bram_14.ex_mem_0[lflat(row,COLUMNS-1)] !== '0) begin
                            $display("  FAIL: Ex[lane %0d][%0d][127] nonzero", lane, row);
                            $finish;
                        end
                    15: if (dut.bram_15.ex_mem_0[lflat(row,COLUMNS-1)] !== '0) begin
                            $display("  FAIL: Ex[lane %0d][%0d][127] nonzero", lane, row);
                            $finish;
                        end
                endcase
            end
        end
        $display("  PASS");

        // ─────────────────────────────────────────────────────
        // TEST 7: Cross-lane propagation
        // Source at global (8,8) = lane 1 local (0,8). Run 20 more iterations.
        // Wave travels downward through lane 1 (8 rows) into lane 2.
        // A broken halo leaves lane 2 all-zero indefinitely.
        // ─────────────────────────────────────────────────────
        $display("TEST 7: Cross-lane propagation (20 more iterations)");
        repeat(20) next_iter;

        nonzero_found = 1'b0;
        for (row = 0; row < ROWS && !nonzero_found; row++) begin
            for (col = 0; col < COLUMNS && !nonzero_found; col++) begin
                if (dut.bram_2.ey_mem_0[lflat(row, col)] !== '0)
                    nonzero_found = 1'b1;
            end
        end
        if (!nonzero_found) begin
            $display("  FAIL: lane 2 Ey all-zero — halo likely broken");
            $finish;
        end
        $display("  PASS: lane 2 has nonzero Ey after cross-lane propagation");

        // ─────────────────────────────────────────────────────
        // TEST 8: solver_done re-fires on the next iteration
        // ─────────────────────────────────────────────────────
        $display("TEST 8: solver_done re-fires on repeated iteration");
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
            $display("  FAIL: solver_done did not re-fire");
            $finish;
        end
        $display("  PASS");

        // ─────────────────────────────────────────────────────
        // TEST 9: rst halts the solver — solver_done stays low
        // ─────────────────────────────────────────────────────
        $display("TEST 9: rst halts solver mid-run");
        solver_enable = 1'b1;
        repeat(100) @(posedge clk);
        rst = 1'b1;
        @(posedge clk);
        rst = 1'b0;
        repeat(5) @(posedge clk);
        solver_enable = 1'b0;
        repeat(10) @(posedge clk);
        if (solver_done) begin
            $display("  FAIL: solver_done spuriously high after rst + disable");
            $finish;
        end
        $display("  PASS");

        $display("ALL TESTS PASSED");
        $finish;
    end

endmodule
