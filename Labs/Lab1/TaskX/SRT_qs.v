`timescale 1ns / 1ps

// ========================================================
// 真双端口 BRAM（读优先）
// ========================================================
module dual_port_bram #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 10
)(
    input  wire                  clk,
    // 端口 A
    input  wire                  wea,
    input  wire [ADDR_WIDTH-1:0] addra,
    input  wire [DATA_WIDTH-1:0] dina,
    output reg  [DATA_WIDTH-1:0] douta,
    // 端口 B
    input  wire                  web,
    input  wire [ADDR_WIDTH-1:0] addrb,
    input  wire [DATA_WIDTH-1:0] dinb,
    output reg  [DATA_WIDTH-1:0] doutb
);
    reg [DATA_WIDTH-1:0] ram [0:(1<<ADDR_WIDTH)-1];
    initial begin
        $readmemh("E:/Computer-Organization-and-Design-26SP/Labs/Lab1/Task3/attachments/data.txt", ram);
    end
    always @(posedge clk) begin
        if (wea) ram[addra] <= dina;
        douta <= ram[addra];
    end
    always @(posedge clk) begin
        if (web) ram[addrb] <= dinb;
        doutb <= ram[addrb];
    end
endmodule


// ========================================================
// 快速排序主模块 SRT（固定 pivot 为区间最后一个元素）
// ========================================================
module SRTX2 (
    input  wire        clk,
    input  wire        rstn,
    input  wire        mode,      // 0-降序，1-升序
    input  wire        start,     // 启动信号
    input  wire [9:0]  addr,      // 查看地址（基于开关输入）

    output reg         done,      // 排序结束标志
    output wire [31:0] data,      // addr 对应地址上的数据
    output reg  [31:0] count      // 排序所需时钟周期数
);

    // BRAM 接口
    reg  [9:0]  bram_addra, bram_addrb;
    reg  [31:0] bram_dina,  bram_dinb;
    reg         bram_wea,   bram_web;
    wire [31:0] bram_douta, bram_doutb;

    dual_port_bram #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(10)
    ) bram (
        .clk    (clk),
        .wea    (bram_wea),
        .addra  (bram_addra),
        .dina   (bram_dina),
        .douta  (bram_douta),

        .web    (bram_web),
        .addrb  (bram_addrb),
        .dinb   (bram_dinb),
        .doutb  (bram_doutb)
    );

    assign data = bram_douta;

    // --------------------------------------------------------
    // 硬件栈存储 {low, high} 区间索引对
    // 使用 11 位有符号数防止 i = low - 1 时出现下溢
    // --------------------------------------------------------
    reg [21:0] stack [0:1023]; 
    reg [10:0] sp; // 栈顶指针

    // --------------------------------------------------------
    // 状态机定义
    // --------------------------------------------------------
    localparam S_IDLE             = 5'd0;   // 空闲/等待
    localparam S_POP              = 5'd1;   // 出栈：从栈中取出子数组 [low, high]；若栈空则排序完成
    localparam S_READ_PIVOT       = 5'd2;   // 读取基准：发送地址 high 到 BRAM，读取 bram[high] 作为基准（pivot）
    localparam S_WAIT_PIVOT       = 5'd3;   // 等待 BRAM 同步读取延迟
    localparam S_LATCH_PIVOT      = 5'd4;   // 锁存基准值：pivot_val = bram[high]，初始化 i = low - 1, j = low
    localparam S_LOOP_COND        = 5'd5;   // 循环条件：判断 j < high，决定继续分区或结束循环
    localparam S_WAIT_J           = 5'd6;   // 等待 bram[j] 读取完成
    localparam S_LATCH_J          = 5'd7;   // 锁存 bram[j] 到 val_j
    localparam S_CMP              = 5'd8;   // 比较：判断 val_j 与 pivot_val 大小，决定是否交换
    localparam S_WAIT_I           = 5'd9;   // 等待 bram[i] 读取完成
    localparam S_LATCH_I          = 5'd10;  // 锁存 bram[i] 到 val_i
    localparam S_SWAP             = 5'd11;  // 交换元素：交叉写入 bram[i] = val_j, bram[j] = val_i
    localparam S_SWAP_WAIT        = 5'd12;  // 交换写入等待
    localparam S_SWAP_PIVOT_READ  = 5'd13;  // 读取 i+1 处的值，准备与 pivot 进行交换
    localparam S_WAIT_PIVOT_SWAP  = 5'd14;  // 等待 bram[i+1] 读取完成
    localparam S_LATCH_PIVOT_SWAP = 5'd15;  // 锁存 bram[i+1] 到 val_i1
    localparam S_SWAP_PIVOT_WRITE = 5'd16;  // 写入基准：将 pivot 与 bram[i+1] 交换，基准归位
    localparam S_PUSH             = 5'd17;  // pivot 写入等待，同时将分区产生的子数组 [low, pivot-1] 和 [pivot+1, high] 压栈
    localparam S_DONE             = 5'd18;  // 排序完成

    reg [4:0] current_state, next_state;
    
    reg signed [10:0] low, high;           // 当前子数组的起始/结束索引
    reg signed [10:0] i;                   // 区间内基准值左侧（根据 mode 决定更大/更小）元素的索引上界
    reg signed [10:0] j;                   // 遍历当前区间
    reg signed [10:0] pivot_idx;           // 基准值最终所在的索引位置
    
    reg [31:0] pivot_val;                  // 基准值，选取 bram[high] 作为基准
    reg [31:0] val_j;                      // bram[j] 的值，当前扫描到的元素
    reg [31:0] val_i;                      // 一轮遍历中执行交换操作时暂存 bram[i] 的值
    reg [31:0] val_i1;                     // 在基准归位时暂存 bram[i+1] 的值

    // --------------------------------------------------------
    // 主控时序逻辑
    // --------------------------------------------------------
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            current_state <= S_IDLE;
            count         <= 0;
            sp            <= 0;
            bram_wea      <= 0;
            bram_web      <= 0;
            bram_addra    <= 0;
            bram_addrb    <= 0;
            bram_dina     <= 0;
            bram_dinb     <= 0;
            low           <= 0;
            high          <= 0;
            i             <= 0;
            j             <= 0;
            pivot_idx     <= 0;
            pivot_val     <= 0;
            val_j         <= 0;
            val_i         <= 0;
            val_i1        <= 0;
        end
        else begin
            current_state <= next_state;
            case (current_state)
                S_IDLE: begin
                    bram_wea    <= 0;
                    bram_web    <= 0;
                    bram_addra  <= addr; // 开放给拨码开关查看
                    
                    if (start) begin
                        sp          <= 1;
                        stack[0]    <= {11'sd0, 11'sd1023}; // 初始化压入整个数组范围
                        count       <= 0;
                    end
                end

                S_POP: begin
                    count <= count + 1;
                    bram_wea <= 0;
                    bram_web <= 0;
                    if (sp != 0) begin  // 栈非空，读出 {low, high} 数据对并出栈
                        low   <= stack[sp-1][21:11];
                        high  <= stack[sp-1][10:0];
                        sp    <= sp - 1;
                    end
                end

                S_READ_PIVOT: begin
                    count <= count + 1;
                    bram_addra <= high; // 固定取最后一个元素作为基准
                end
                
                S_WAIT_PIVOT: begin // 等待读取 bram[high]
                    count <= count + 1; 
                end
                
                S_LATCH_PIVOT: begin
                    count <= count + 1;
                    pivot_val <= bram_douta;
                    
                    // 初始化 pivot 左侧下标和遍历起点
                    i <= low - 1;
                    j <= low;
                end

                S_LOOP_COND: begin
                    count <= count + 1;
                    if (j < high) begin // 还没有遍历完所有元素
                        bram_addra <= j;
                    end
                end

                S_WAIT_J: begin // 等待读取 bram[j]
                    count <= count + 1; 
                end
                
                S_LATCH_J: begin 
                    count <= count + 1; 
                    val_j <= bram_douta; 
                end
                
                S_CMP: begin
                    count <= count + 1;
                    // 判断是否满足交换条件
                    if ((mode == 1'b1 && val_j <= pivot_val) || 
                        (mode == 1'b0 && val_j >= pivot_val)) begin
                        i <= i + 1;
                        bram_addrb <= i + 1; // 准备读取 bram[i] 进行交换；交换后 bram[i] 仍需要判断，j 不变
                    end
                    else begin
                        j <= j + 1;
                    end
                end

                S_WAIT_I: begin // 等待读取 bram[i]
                    count <= count + 1; 
                end
                
                S_LATCH_I: begin 
                    count <= count + 1; 
                    val_i <= bram_doutb; 
                end
                
                S_SWAP: begin
                    count <= count + 1;
                    // 交叉写入，交换数据
                    bram_wea   <= 1;
                    bram_addra <= i;
                    bram_dina  <= val_j;

                    bram_web   <= 1;
                    bram_addrb <= j;
                    bram_dinb  <= val_i;
                    j <= j + 1;
                end
                
                S_SWAP_WAIT: begin
                    count <= count + 1;
                    // 写入只需一个周期，立刻关闭写使能
                    bram_wea <= 0;
                    bram_web <= 0;
                end

                // --- 循环结束后，将基准元素放到 i+1 索引处---
                S_SWAP_PIVOT_READ: begin
                    count <= count + 1;
                    pivot_idx <= i + 1;
                    bram_addra <= i + 1;
                end
                
                S_WAIT_PIVOT_SWAP: begin // 等待读取 bram[i+1]
                    count <= count + 1; 
                end
                
                S_LATCH_PIVOT_SWAP: begin 
                    count <= count + 1; 
                    val_i1 <= bram_douta;
                end
                
                S_SWAP_PIVOT_WRITE: begin
                    count <= count + 1;
                    bram_wea <= 1;
                    bram_addra <= pivot_idx;
                    bram_dina <= pivot_val;

                    bram_web <= 1;
                    bram_addrb <= high;
                    bram_dinb <= val_i1;
                end

                // --- 将产生的新子数组索引压入栈 ---
                S_PUSH: begin
                    count <= count + 1;
                    bram_wea <= 0; bram_web <= 0;
                    
                    if (low < pivot_idx - 1 && pivot_idx + 1 < high) begin // 左右区间同时非空
                        stack[sp]   <= {low, pivot_idx - 11'sd1};
                        stack[sp+1] <= {pivot_idx + 11'sd1, high};
                        sp <= sp + 2;
                    end
                    else if (low < pivot_idx - 1) begin                     // 仅左区间非空
                        stack[sp] <= {low, pivot_idx - 11'sd1};
                        sp <= sp + 1;
                    end
                    else if (pivot_idx + 1 < high) begin                    // 仅右区间非空
                        stack[sp] <= {pivot_idx + 11'sd1, high};
                        sp <= sp + 1;
                    end
                end

                S_DONE: begin
                    bram_addra <= addr; // 开放查看
                end
            endcase
        end
    end

    // --------------------------------------------------------
    // 状态转换组合逻辑
    // --------------------------------------------------------
    always @(*) begin
        next_state = current_state;
        case (current_state)
            S_IDLE:
                if (start)
                    next_state = S_POP;
                else
                    next_state = S_IDLE;

            S_POP:
                if (sp == 0)    // 栈空，则排序完成
                    next_state = S_DONE;
                else
                    next_state = S_READ_PIVOT;

            S_READ_PIVOT:       // 读出基准元素
                next_state = S_WAIT_PIVOT;

            S_WAIT_PIVOT:       // 等待读出 bram[high]
                next_state = S_LATCH_PIVOT;

            S_LATCH_PIVOT:
                next_state = S_LOOP_COND;

            S_LOOP_COND:
                if (j < high)   // 还没有遍历完所有元素
                    next_state = S_WAIT_J;
                else            // 遍历完成，下一步将基准元素放到正确位置
                    next_state = S_SWAP_PIVOT_READ;

            S_WAIT_J:           // 等待读出 bram[j]
                next_state = S_LATCH_J;

            S_LATCH_J:
                next_state = S_CMP;

            S_CMP:
                if ((mode == 1'b1 && val_j <= pivot_val) ||         // 升序情况下(1)，当前的数小于 pivot
                    (mode == 1'b0 && val_j >= pivot_val))           // 降序情况下(0)，当前的数大于 pivot
                    next_state = S_WAIT_I;
                else
                    next_state = S_LOOP_COND;

            S_WAIT_I:           // 等待读出 bram[i]
                next_state = S_LATCH_I;

            S_LATCH_I:
                next_state = S_SWAP;

            S_SWAP:
                next_state = S_SWAP_WAIT;

            S_SWAP_WAIT:
                next_state = S_LOOP_COND;

            S_SWAP_PIVOT_READ:
                next_state = S_WAIT_PIVOT_SWAP;

            S_WAIT_PIVOT_SWAP:  // 等待读出 bram[i+1]
                next_state = S_LATCH_PIVOT_SWAP;

            S_LATCH_PIVOT_SWAP:
                next_state = S_SWAP_PIVOT_WRITE;

            S_SWAP_PIVOT_WRITE:
                next_state = S_PUSH;

            S_PUSH:
                next_state = S_POP;

            S_DONE:
                next_state = S_IDLE;
            default:
                next_state = S_IDLE;
        endcase
    end

    // --------------------------------------------------------
    // 输出逻辑
    // --------------------------------------------------------
    always @(*) begin
        done = (current_state == S_DONE);
    end

endmodule
