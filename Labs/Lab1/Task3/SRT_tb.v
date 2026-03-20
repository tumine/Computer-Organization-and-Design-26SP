`timescale 1ns / 1ps

module SRT_tb;

    reg         clk;
    reg         rstn;
    reg         mode;      // 0: 降序, 1: 升序
    reg         start;
    reg  [9:0]  addr;
    wire [0:0]  done;
    wire [31:0] data;
    wire [31:0] count;

    integer error_cnt;      // 记录不符合排序要求的逆序数

    // DUT
    SRT dut (
        .clk   (clk),
        .rstn  (rstn),
        .mode  (mode),
        .start (start),
        .addr  (addr),
        .done  (done),
        .data  (data),
        .count (count)
    );

    // 100MHz
    always #5 clk = ~clk;

    // 等待排序结束（带超时保护）
    task wait_sort_done;
        integer cyc;
        begin
            cyc = 0;
            while ((done !== 1'b1) && (cyc < 7000000)) begin
                @(posedge clk);
                cyc = cyc + 1;
            end

            // 让状态机从 DONE 回到 IDLE，方便通过 addr 读数
            @(posedge clk);
        end
    endtask

    // 检查当前内存是否有序
    task check_sorted;
        input mode_sel; // 1: 升序, 0: 降序
        integer k;
        reg [31:0] prev_val;
        reg [31:0] curr_val;
        begin
            addr = 10'd0;
            @(posedge clk);
            @(posedge clk);
            prev_val = data;

            for (k = 1; k < 1024; k = k + 1) begin
                addr = k[9:0];
                @(posedge clk);
                @(posedge clk);
                curr_val = data;

                if (mode_sel) begin
                    if (prev_val > curr_val) begin
                        error_cnt = error_cnt + 1;
                    end
                end else begin
                    if (prev_val < curr_val) begin
                        error_cnt = error_cnt + 1;
                    end
                end

                prev_val = curr_val;
            end
        end
    endtask

    initial begin
        clk      = 1'b0;
        rstn     = 1'b0;
        mode     = 1'b1;
        start    = 1'b0;
        addr     = 10'd0;
        error_cnt = 0;

        // 复位
        repeat (4) @(posedge clk);
        rstn = 1'b1;
        repeat (2) @(posedge clk);

        // // ===============================
        // // Case 1: 升序排序
        // // ===============================
        // mode  = 1'b1;
        // start = 1'b1;
        // @(posedge clk);
        // start = 1'b0;

        // wait_sort_done();
        // check_sorted(1'b1);

        // @(posedge clk);
        // #100;
        // ===============================
        // Case 2: 降序排序
        // 对当前数据再次排序，验证另一种模式
        // ===============================
        mode  = 1'b0;
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        wait_sort_done();
        check_sorted(1'b0);

        #20;
        $finish;
    end

endmodule
