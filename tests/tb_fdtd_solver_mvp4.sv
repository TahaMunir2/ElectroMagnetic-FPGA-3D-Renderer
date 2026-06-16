`timescale 1ns/1ps

module tb_fdtd_solver_mvp4;

    localparam CELLS      = 64;
    localparam CELL_WIDTH = 6;
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
    logic [DATA_WIDTH-1:0]        source_in;
    logic                         source_valid;
    logic [2*CELL_WIDTH-1:0]      source_addr;
    logic [1:0]                   preset;
    logic [3:0]                   slit_w;
    logic                         mat_en;
    logic signed [DATA_WIDTH-1:0] cb_mat;

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
        .e_phase(),
        .preset(preset),
        .slit_w(slit_w),
        .mat_en(mat_en),
        .cb_mat(cb_mat)
    );

    function automatic integer flat(input integer row, input integer col);
        flat = row * CELLS + col;
    endfunction

    task clear_mem;
        for (int i = 0; i < GRID; i++) begin
            ey_mem[i] = '0;
            ex_mem[i] = '0;
            bz_mem[i] = '0;
        end
    endtask

    task do_reset;
        solver_enable = 1'b0;
        @(posedge clk);
        rst = 1'b1;
        @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);
    endtask

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
                $display("FAIL: timeout after %0d cycles", max_cycles);
                $finish;
            end
        end
    endtask

    integer cycles_taken;

    initial begin
        clear_mem();
        solver_enable = 1'b0;
        source_valid  = 1'b0;
        source_in     = '0;
        source_addr   = flat(8, 8);
        preset        = 2'd0;
        slit_w        = 4'd4;
        mat_en        = 1'b0;
        cb_mat        = -16'sd717;

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
            $display("FAIL test 1: cycles=%0d expected=%0d", cycles_taken, 2*GRID+4);
            $finish;
        end
        $display("PASS test 1: %0d cycles", cycles_taken);

        if (ey_mem[flat(8,8)] == '0) begin
            $display("FAIL test 2: ey[8,8] zero after inject");
            $finish;
        end
        $display("PASS test 2: source injected ey[8,8]=%0d", $signed(ey_mem[flat(8,8)]));

        begin : t3
            integer r;
            for (r = 0; r < CELLS; r++) begin
                if (ey_mem[flat(0, r)] !== '0) begin
                    $display("FAIL test 3: ey[0,%0d]=%0d non-zero", r, $signed(ey_mem[flat(0,r)]));
                    $finish;
                end
                if (ey_mem[flat(CELLS-1, r)] !== '0) begin
                    $display("FAIL test 3: ey[%0d,%0d]=%0d non-zero", CELLS-1, r, $signed(ey_mem[flat(CELLS-1,r)]));
                    $finish;
                end
            end
        end
        $display("PASS test 3: ey boundary rows zero");

        clear_mem();
        ey_mem[flat(5, 32)] = 16'sd8192;
        preset       = 2'd1;
        slit_w       = 4'd4;
        cb_mat       = -16'sd717;
        source_valid = 1'b0;
        do_reset();
        solver_enable = 1'b1;
        wait_done(2*GRID + 10);

        if (ey_mem[flat(5, 32)] !== '0) begin
            $display("FAIL test 4: wall did not zero ey[5,32], got %0d", $signed(ey_mem[flat(5,32)]));
            $finish;
        end
        $display("PASS test 4: wall zeroed ey outside slit");

        clear_mem();
        ey_mem[flat(32, 32)] = 16'sd8192;
        preset        = 2'd1;
        slit_w        = 4'd4;
        cb_mat        = -16'sd717;
        source_valid  = 1'b0;
        do_reset();
        solver_enable = 1'b1;
        wait_done(2*GRID + 10);

        if (ey_mem[flat(32, 32)] == '0) begin
            $display("FAIL test 5: slit zeroed ey[32,32]");
            $finish;
        end
        $display("PASS test 5: slit preserved ey[32,32]=%0d", $signed(ey_mem[flat(32,32)]));

        clear_mem();
        bz_mem[flat(32, 40)] = 16'sd8192;
        preset        = 2'd0;
        mat_en        = 1'b1;
        cb_mat        = 16'sd0;
        source_valid  = 1'b0;
        do_reset();
        solver_enable = 1'b1;
        wait_done(2*GRID + 10);

        if (ey_mem[flat(32, 40)] !== '0) begin
            $display("FAIL test 6: mat_en + cb_mat=0 should suppress ey, got %0d", $signed(ey_mem[flat(32,40)]));
            $finish;
        end
        $display("PASS test 6: mat_en + cb_mat=0 suppresses right-half ey update");

        clear_mem();
        bz_mem[flat(32, 40)] = 16'sd8192;
        preset        = 2'd0;
        mat_en        = 1'b1;
        cb_mat        = -16'sd717;
        source_valid  = 1'b0;
        do_reset();
        solver_enable = 1'b1;
        wait_done(2*GRID + 10);

        if (ey_mem[flat(32, 40)] == '0) begin
            $display("FAIL test 7: mat_en + cb_mat=-717 should drive ey non-zero");
            $finish;
        end
        $display("PASS test 7: mat_en + cb_mat=-717 drives ey[32,40]=%0d", $signed(ey_mem[flat(32,40)]));

        clear_mem();
        bz_mem[flat(32, 40)] = 16'sd8192;
        preset        = 2'd0;
        mat_en        = 1'b0;
        cb_mat        = 16'sd0;
        source_valid  = 1'b0;
        do_reset();
        solver_enable = 1'b1;
        wait_done(2*GRID + 10);

        if (ey_mem[flat(32, 40)] == '0) begin
            $display("FAIL test 8: mat_en=0 should ignore cb_mat and update ey, got 0");
            $finish;
        end
        $display("PASS test 8: mat_en=0 ignores cb_mat, ey[32,40]=%0d", $signed(ey_mem[flat(32,40)]));

        $display("all 8 tests passed");
        $finish;
    end

endmodule
