`timescale 1ns / 1ps

// ========================================================
// 快速排序主模块 SRT（固定 pivot 为区间最后一个元素）
// ========================================================
module SRTX2_ipb (
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

    // 真双端口 BRAM（ENA Pin 始终启用）
    blk_mem_gen_1 dual_blk_mem_wfirst (
        .clka(clk), 
        .wea(bram_wea), 
        .addra(bram_addra), 
        .dina(bram_dina), 
        .douta(bram_douta),

        .clkb(clk),
        .web(bram_web),
        .addrb(bram_addrb),
        .dinb(bram_dinb), 
        .doutb(bram_doutb)
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
    localparam S_IDLE                   = 5'd0;   // 空闲/等待
    localparam S_POP                    = 5'd1;   // 出栈：从栈中取出子数组 [low, high]；若栈空则排序完成
    localparam S_READ_PIVOT             = 5'd2;   // 读取基准：发送地址 high 到 BRAM，读取 bram[high] 作为基准（pivot）
    localparam S_WAIT_PIVOT             = 5'd3;   // 等待 BRAM 同步读取延迟
    localparam S_LATCH_PIVOT            = 5'd4;   // 锁存基准值：pivot_val = bram[high]，初始化 i = low - 1, j = low
    localparam S_LOOP_COND              = 5'd5;   // 循环条件：判断 j < high，决定继续分区或结束循环
    localparam S_WAIT_J                 = 5'd6;   // 等待 bram[j] 读取完成
    localparam S_LATCH_J                = 5'd7;   // 锁存 bram[j] 到 val_j
    localparam S_CMP                    = 5'd8;   // 比较：判断 val_j 与 pivot_val 大小，决定是否交换
    localparam S_WAIT_I                 = 5'd9;   // 等待 bram[i] 读取完成
    localparam S_LATCH_I                = 5'd10;  // 锁存 bram[i] 到 val_i
    localparam S_SWAP1                  = 5'd11;  // 交换写入端口 A：写入 bram[i] = val_j
    localparam S_SWAP2                  = 5'd12;  // 交换写入端口 B：写入 bram[j] = val_i（兼关闭 A 端口写入）
    localparam S_SWAP_WAIT1             = 5'd13;  // 交换写入：关闭 B 端口写入（兼等待 A 端口写入）
    localparam S_SWAP_WAIT2             = 5'd14;  // 交换写入：等待 B 端口写入
    localparam S_SWAP_PIVOT_READ        = 5'd15;  // 读取 i+1 处的值，准备与 pivot 进行交换
    localparam S_WAIT_PIVOT_SWAP        = 5'd16;  // 等待 bram[i+1] 读取完成
    localparam S_LATCH_PIVOT_SWAP       = 5'd17;  // 锁存 bram[i+1] 到 val_i1
    localparam S_SWAP_PIVOT_WRITE1      = 5'd18;  // 写入 A 端口：将 pivot 写入 bram[i+1]
    localparam S_SWAP_PIVOT_WRITE2      = 5'd19;  // 写入 B 端口：将 val_i1 写入 bram[high]（兼关闭 A 端口写入）
    localparam S_SWAP_PIVOT_WAIT1       = 5'd20;  // pivot 归位：关闭 B 端口写入（兼等待 A 端口写入）
    localparam S_SWAP_PIVOT_WAIT2       = 5'd21;  // pivot 归位：等待 B 端口写入
    localparam S_PUSH                   = 5'd22;  // 将分区产生的子数组 [low, pivot-1] 和 [pivot+1, high] 压栈
    localparam S_DONE                   = 5'd23;  // 排序完成

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
                    else begin
                        // 循环结束，提前计算 pivot_idx 供 S_PUSH 使用
                        pivot_idx <= i + 1;
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
                        if (i + 1 == j) begin
                            // i+1 == j: 元素与自身交换无意义，跳过，直接前进
                            j <= j + 1;
                        end
                        else begin
                            bram_addrb <= i + 1; // 准备读取 bram[i+1] 进行交换
                        end
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
                
                S_SWAP1: begin
                    count <= count + 1;
                    // 先只通过 A 端口写 bram[i] = val_j
                    bram_wea    <= 1;
                    bram_addra  <= i;
                    bram_dina   <= val_j;
                    // B 端口本周期不操作，预填数据但不使能写
                    bram_web    <= 0;
                    bram_dinb   <= val_i;
                end
                
                S_SWAP2: begin
                    count <= count + 1;
                    // 关闭 A 写，开启 B 写 bram[j] = val_i
                    bram_wea    <= 0;
                    bram_addrb  <= j;
                    bram_web    <= 1;
                    j <= j + 1;
                end
                
                S_SWAP_WAIT1: begin
                    count <= count + 1;
                    bram_web <= 0;
                end

                S_SWAP_WAIT2: begin
                    count <= count + 1;
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
                
                S_SWAP_PIVOT_WRITE1: begin  // 先写 A 端口，把 pivot 归位
                    count <= count + 1;
                    bram_wea <= 1;
                    bram_addra <= pivot_idx;
                    bram_dina <= pivot_val;
                    // B 端口本周期不操作，预填数据但不使能写，地址推迟到 WRITE2 再设
                    bram_web <= 0;
                    bram_dinb <= val_i1;
                end
                
                S_SWAP_PIVOT_WRITE2: begin  // 再写 B 端口
                    count <= count + 1;
                    bram_wea <= 0;
                    bram_addrb <= high;  // 此时 A 端口写已完成，设 B 地址不会冲突
                    bram_web <= 1;
                end
                
                S_SWAP_PIVOT_WAIT1: begin
                    count <= count + 1;
                    bram_web <= 0;
                end

                S_SWAP_PIVOT_WAIT2: begin
                    count <= count + 1;
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
                else if (i + 1 == high) // pivot 已经在正确位置，无需归位交换
                    next_state = S_PUSH;
                else            // 遍历完成，下一步将基准元素放到正确位置
                    next_state = S_SWAP_PIVOT_READ;

            S_WAIT_J:           // 等待读出 bram[j]
                next_state = S_LATCH_J;

            S_LATCH_J:
                next_state = S_CMP;

            S_CMP:
                if ((mode == 1'b1 && val_j <= pivot_val) ||         // 升序情况下(1)，当前的数小于 pivot
                    (mode == 1'b0 && val_j >= pivot_val)) begin     // 降序情况下(0)，当前的数大于 pivot
                    if (i + 1 == j)       // 自交换无意义，跳过
                        next_state = S_LOOP_COND;
                    else
                        next_state = S_WAIT_I;
                end
                else
                    next_state = S_LOOP_COND;

            S_WAIT_I:           // 等待读出 bram[i]
                next_state = S_LATCH_I;

            S_LATCH_I:
                next_state = S_SWAP1;

            S_SWAP1:
                next_state = S_SWAP2;

            S_SWAP2:
                next_state = S_SWAP_WAIT1;

            S_SWAP_WAIT1:
                next_state = S_SWAP_WAIT2;
                
            S_SWAP_WAIT2:
                next_state = S_LOOP_COND;

            S_SWAP_PIVOT_READ:
                next_state = S_WAIT_PIVOT_SWAP;

            S_WAIT_PIVOT_SWAP:  // 等待读出 bram[i+1]
                next_state = S_LATCH_PIVOT_SWAP;

            S_LATCH_PIVOT_SWAP:
                next_state = S_SWAP_PIVOT_WRITE1;

            S_SWAP_PIVOT_WRITE1:
                next_state = S_SWAP_PIVOT_WRITE2;

            S_SWAP_PIVOT_WRITE2:
                next_state = S_SWAP_PIVOT_WAIT1;

            S_SWAP_PIVOT_WAIT1:
                next_state = S_SWAP_PIVOT_WAIT2;
                
            S_SWAP_PIVOT_WAIT2:
                next_state = S_PUSH;

            S_PUSH:
                next_state = S_POP;

            S_DONE:
                next_state = S_DONE;  // 保持在 DONE，使 done 信号持续拉高
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

module SegmentX2_ipb (
    input           [ 0 : 0]            clk_100m        ,
    input           [ 0 : 0]            rst_n           ,

    input           [31 : 0]            display_data    ,

    output  reg     [ 7 : 0]            an              ,      // Connecting segments display
    output  reg     [ 6 : 0]            data                   // Connecting segments display      
);

    reg  [ 2 : 0]     seg_cnt     ;
    reg  [ 3 : 0]     seg_data    ;
    reg  [16 : 0]     cnt400      ;


    always @(posedge clk_100m) begin
        if (!rst_n) begin
            cnt400  <= 0;
            seg_cnt <= 0;
        end
        else begin
            if (cnt400 > 'D49999) begin
                cnt400 <= 0;
                if (seg_cnt == 'D7)
                    seg_cnt <= 0;
                else
                    seg_cnt <= seg_cnt + 'B1;
            end
            else
                cnt400 <= cnt400 + 'B1;
        end
    end
    
    always @(*) begin
        case (seg_cnt)
             'D0: begin an = 8'B11111110; seg_data = display_data[0 +: 4]; end
             'D1: begin an = 8'B11111101; seg_data = display_data[4 +: 4]; end
             'D2: begin an = 8'B11111011; seg_data = display_data[8 +: 4]; end
             'D3: begin an = 8'B11110111; seg_data = display_data[12 +: 4]; end
             'D4: begin an = 8'B11101111; seg_data = display_data[16 +: 4]; end
             'D5: begin an = 8'B11011111; seg_data = display_data[20 +: 4]; end
             'D6: begin an = 8'B10111111; seg_data = display_data[24 +: 4]; end
             'D7: begin an = 8'B01111111; seg_data = display_data[28 +: 4]; end
        endcase   
        case (seg_data)
            4'H0: data = 7'B0000001;  //0
            4'H1: data = 7'B1001111;  //1
            4'H2: data = 7'B0010010;  //2
            4'H3: data = 7'B0000110;  //3
            4'H4: data = 7'B1001100;  //4
            4'H5: data = 7'B0100100;  //5
            4'H6: data = 7'B0100000;  //6
            4'H7: data = 7'B0001111;  //7
            4'H8: data = 7'B0000000;  //8
            4'H9: data = 7'B0000100;  //9
            4'Ha: data = 7'B0001000;  //A
            4'Hb: data = 7'B1100000;  //B
            4'Hc: data = 7'B0110001;  //C
            4'Hd: data = 7'B1000010;  //D
            4'He: data = 7'B0110000;  //E
            4'Hf: data = 7'B0111000;  //F
        endcase
    end
endmodule

module TopX2_ipb (
    input               clk,
    input               rstn,           // 按键复位
    input               start,          // 按键启动排序
    input               mode,           // 开关选择排序模式：0-降序，1-升序
    input  [9:0]        addr,           // 开关输入查看地址
    output [7:0]        an,             // 数码管位选
    output [6:0]        data,           // 数码管段选
    output              done,           // LED指示排序完成
    output [15:0]       count           // 排序时钟周期数
);

wire [31:0] srt_count;
wire [31:0] mem_data;                   // BRAM 读出数据

// 实例化 SRT 排序模块
SRTX2_ipb srt (
    .clk(clk),
    .rstn(rstn),
    .mode(mode),
    .start(start),
    .addr(addr),
    .done(done),
    .data(mem_data),
    .count(srt_count)
);

// 数码管显示：显示 data 或 count
wire [31:0] display_data = done ? count : mem_data;

SegmentX2_ipb segment (
    .clk_100m(clk),
    .rst_n(rstn),
    .display_data(display_data),
    .an(an),
    .data(data)
);

assign count = srt_count[25:10];

endmodule
