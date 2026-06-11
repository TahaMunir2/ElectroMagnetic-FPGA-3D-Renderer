`timescale 1ns/1ps

module tb_top_fdtd_quad_lane;

    localparam TOTAL_ROWS = 64;
    localparam ROWS       = 16;
    localparam COLUMNS    = 64;
    localparam GRID_SIZE  = ROWS * COLUMNS;   // 1024 per lane
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

    // local address within a lane: (local_row, col) → 0..GRID_SIZE-1
    function automatic integer lflat(input integer local_row, input integer col);
        lflat = local_row * COLUMNS + col;
    endfunction

    // Wait for solver_done, timeout after max_cycles
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

    // Toggle solver_enable to kick off one more iteration.
    // Drive enable at negedge so it is stable before the next posedge
    // — avoids a race where always_ff and the initial block evaluate at
    // the same active region and always_ff sees the wrong enable value.
    task automatic next_iter;
        begin
            @(negedge clk); solver_enable = 1'b0;   // stable before posedge
            @(posedge clk);                          // posedge sees enable=0 → reset
            @(negedge clk); solver_enable = 1'b1;   // stable before posedge
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

        // ─────────────────────────────────────────────────────
        // TEST 1: solver_done fires after exactly 2*GRID_SIZE cycles
        // ─────────────────────────────────────────────────────
        $display("TEST 1: solver_done timing");
        source_in     = 16'sd8192;
        source_valid  = 1'b1;
        source_addr   = 8 * COLUMNS + 8;   // global (8,8) → lane 0 local (8,8)
        solver_enable = 1'b1;

        cycles_taken = 0;
        @(posedge clk);
        while (!solver_done) begin
            @(posedge clk);
            cycles_taken++;
        end
        cycles_taken++;
        $display("  solver_done after %0d cycles (expected %0d)", cycles_taken, 2*GRID_SIZE);
        if (cycles_taken !== 2*GRID_SIZE) begin
            $display("  FAIL");
            $finish;
        end
        $display("  PASS");

        // ─────────────────────────────────────────────────────
        // TEST 2: Source injection — Ey at (8,8) must be nonzero
        // ─────────────────────────────────────────────────────
        $display("TEST 2: Source injection Ey(8,8) nonzero");
        if ($signed(dut.bram_0.ey_mem_0[lflat(8, 8)]) == 0) begin
            $display("  FAIL: Ey[8][8] = 0 after source injection");
            $finish;
        end
        $display("  Ey[8][8] = %0d  PASS", $signed(dut.bram_0.ey_mem_0[lflat(8, 8)]));

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
        // TEST 4: Ey bottom boundary zero — global row 63 (lane 3 local row 15)
        // ─────────────────────────────────────────────────────
        $display("TEST 4: Ey bottom boundary (global row 63) forced zero");
        for (col = 0; col < COLUMNS; col++) begin
            if (dut.bram_3.ey_mem_0[lflat(ROWS-1, col)] !== '0) begin
                $display("  FAIL: Ey[63][%0d] = %0d", col,
                         $signed(dut.bram_3.ey_mem_0[lflat(ROWS-1, col)]));
                $finish;
            end
        end
        $display("  PASS");

        // ─────────────────────────────────────────────────────
        // TEST 5: Ex left boundary zero — col 0 across all lanes
        // ─────────────────────────────────────────────────────
        $display("TEST 5: Ex left boundary (col 0) forced zero");
        for (row = 0; row < ROWS; row++) begin
            if (dut.bram_0.ex_mem_0[lflat(row, 0)] !== '0 ||
                dut.bram_1.ex_mem_0[lflat(row, 0)] !== '0 ||
                dut.bram_2.ex_mem_0[lflat(row, 0)] !== '0 ||
                dut.bram_3.ex_mem_0[lflat(row, 0)] !== '0) begin
                $display("  FAIL: Ex col 0 nonzero at local row %0d", row);
                $finish;
            end
        end
        $display("  PASS");

        // ─────────────────────────────────────────────────────
        // TEST 6: Ex right boundary zero — col 63 across all lanes
        // ─────────────────────────────────────────────────────
        $display("TEST 6: Ex right boundary (col 63) forced zero");
        for (row = 0; row < ROWS; row++) begin
            if (dut.bram_0.ex_mem_0[lflat(row, COLUMNS-1)] !== '0 ||
                dut.bram_1.ex_mem_0[lflat(row, COLUMNS-1)] !== '0 ||
                dut.bram_2.ex_mem_0[lflat(row, COLUMNS-1)] !== '0 ||
                dut.bram_3.ex_mem_0[lflat(row, COLUMNS-1)] !== '0) begin
                $display("  FAIL: Ex col 63 nonzero at local row %0d", row);
                $finish;
            end
        end
        $display("  PASS");

        // ─────────────────────────────────────────────────────
        // TEST 7: Cross-lane propagation
        // Run 20 more iterations with continuous source at (8,8).
        // The wave front travels ~1 cell/iter so after ~21 total
        // iterations it reaches global row ~21 (lane 1 local row 5).
        // Lane 1 must have at least one nonzero Ey cell.
        // A broken halo would leave lane 1 at zero indefinitely.
        // ─────────────────────────────────────────────────────
        $display("TEST 7: Cross-lane propagation (running 20 more iterations)");
        repeat(20) next_iter;

        nonzero_found = 1'b0;
        for (row = 0; row < ROWS && !nonzero_found; row++) begin
            for (col = 0; col < COLUMNS && !nonzero_found; col++) begin
                if (dut.bram_1.ey_mem_0[lflat(row, col)] !== '0)
                    nonzero_found = 1'b1;
            end
        end
        if (!nonzero_found) begin
            $display("  FAIL: lane 1 Ey is all-zero — halo likely broken");
            $finish;
        end
        $display("  PASS: lane 1 has nonzero Ey after cross-lane propagation");

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
            $display("  FAIL: solver_done did not fire on repeated iteration");
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
