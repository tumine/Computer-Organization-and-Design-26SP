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

    // 定义存储器，深度 1024
    reg [DATA_WIDTH-1:0] ram [0:(1<<ADDR_WIDTH)-1];

    initial begin
        // 使用 .txt 文件进行初始化
        $readmemh("attachments/data.txt", ram);
    end

    // 端口 A 同步读写
    always @(posedge clk) begin
        if (wea) ram[addra] <= dina;
        douta <= ram[addra];
    end

    // 端口 B 同步读写
    always @(posedge clk) begin
        if (web) ram[addrb] <= dinb;
        doutb <= ram[addrb];
    end
endmodule


// ========================================================
// 冒泡排序主模块 SRT
// ========================================================
module SRT (
    input  wire        clk,
    input  wire        rstn,
    input  wire        mode,      // 0-降序，1-升序
    input  wire        start,     // 启动信号
    input  wire [9:0]  addr,      // 查看地址（基于开关输入）

    output reg         done,      // 排序结束标志
    output wire [31:0] data,      // addr 对应地址上的数据
    output reg  [31:0] count      // 排序所需时钟周期数
);

    // --------------------------------------------------------
    // BRAM 接口信号定义
    // --------------------------------------------------------
    reg  [9:0]  bram_addra, bram_addrb;
    reg  [31:0] bram_dina,  bram_dinb;
    reg         bram_wea,   bram_web;
    wire [31:0] bram_douta, bram_doutb;

    // 实例化 BRAM
    dual_port_bram #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(10)
    ) bram (
        .clk   (clk),
        .wea   (bram_wea),
        .addra (bram_addra),
        .dina  (bram_dina),
        .douta (bram_douta),
        .web   (bram_web),
        .addrb (bram_addrb),
        .dinb  (bram_dinb),
        .doutb (bram_doutb)
    );

    // 真双端口 BRAM（ENA Pin 始终启用）
    /*
    blk_mem_gen_2 dual_blk_mem_wfirst (
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
    */

    // 查看地址功能映射：空闲或完成时，利用端口 A 读取外部开关指定的地址
    assign data = bram_douta;

    // --------------------------------------------------------
    // 状态机定义
    // --------------------------------------------------------
    localparam S_IDLE  = 3'd0; // 空闲/等待
    localparam S_READ  = 3'd1; // 发送读地址
    localparam S_WAIT  = 3'd2; // 等待 BRAM 同步读取延迟 (1 个周期)
    localparam S_CMP   = 3'd3; // 比较数据，决定是否交换
    localparam S_WRITE = 3'd4; // 写入交换后的数据
    localparam S_DONE  = 3'd5; // 排序完成

    reg [2:0] current_state, next_state;

    reg [9:0] i;       // 外循环: 0 到 1022
    reg [9:0] j;       // 内循环: 1023 到 i + 1

    // --------------------------------------------------------
    // 主控时序逻辑
    // --------------------------------------------------------
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            current_state   <= S_IDLE;
            i               <= 0;
            j               <= 1023;
            count           <= 0;
            bram_wea        <= 0;
            bram_web        <= 0;
            bram_addra      <= 0;
            bram_addrb      <= 0;
            bram_dina       <= 0;
            bram_dinb       <= 0;
        end 
        else begin
            current_state <= next_state;
            case (current_state)
                S_IDLE: begin
                    bram_wea <= 0;
                    bram_web <= 0;

                    // 在空闲状态，将端口 A 开放给拨码开关以便查看数据
                    bram_addra <= addr;
                    
                    if (start) begin    // 检测到开始排序信号，把所有排序中使用的辅助变量初始化
                        i     <= 0;
                        j     <= 1023;
                        count <= 0;
                    end
                end

                S_READ: begin
                    count <= count + 1;
                    bram_wea <= 0;
                    bram_web <= 0;
                    // 发送相邻两个数据的地址给 BRAM 端口 A 和 B
                    bram_addra <= j - 1;
                    bram_addrb <= j;
                end

                S_WAIT: begin   // 缓冲 1 个时钟周期，等待 BRAM 将数据推送到 douta 和 doutb
                    count <= count + 1;
                end

                S_CMP: begin    // douta 和 doutb 数据就绪，比较两个位上的数据大小
                    count <= count + 1;
                    if ((mode == 1'b1 && bram_douta > bram_doutb) || 
                        (mode == 1'b0 && bram_douta < bram_doutb)) begin
                        // 需要交换：将读出的数据交叉写回
                        bram_addra <= j - 1;
                        bram_dina  <= bram_doutb; 
                        bram_wea   <= 1;

                        bram_addrb <= j;
                        bram_dinb  <= bram_douta;
                        bram_web   <= 1;
                    end
                    else begin
                        // 不需要交换，直接跳转到下一个元素
                        if (j > i + 1) begin
                            j     <= j - 1;
                        end
                        else begin
                            if (i < 1022) begin
                                i     <= i + 1;
                                j     <= 1023;
                            end
                        end
                    end
                end

                S_WRITE: begin
                    count <= count + 1;
                    // 写入只需一个周期，立刻关闭写使能
                    bram_wea <= 0;
                    bram_web <= 0;
                    
                    // 索引跳转逻辑
                    if (j > i + 1) begin
                        j     <= j - 1;
                    end
                    else begin
                        if (i < 1022) begin
                            i     <= i + 1;
                            j     <= 1023;
                        end
                    end
                end

                S_DONE: begin
                    // 排序完成后，再次将端口 A 开放给拨码开关以查看数据
                    bram_addra <= addr;
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
                    next_state = S_READ;
                else
                    next_state = S_IDLE; 
            S_READ: // 从内存中读取，直接跳转到 WAIT 状态等待一个时钟周期
                next_state = S_WAIT;
            S_WAIT: // 等待一个时钟周期后读取完毕，跳转到 CMP 状态
                next_state = S_CMP;
            S_CMP:
                if ((mode == 1'b1 && bram_douta > bram_doutb) ||    // 升序情况下(1)，前面的数比后面的数更大
                    (mode == 1'b0 && bram_douta < bram_doutb))      // 降序情况下(0)，前面的数比后面的数更小
                    next_state = S_WRITE;                           // 需要进行数据交换
                else begin  // 否则，直接进行下一轮比较
                    if (j > i + 1 || i < 1022)   // 完整一轮的比较仍未结束，或者后面还有新的一轮比较需要进行
                        next_state = S_READ;
                    else                            // 比较完成
                        next_state = S_DONE;
                end
            S_WRITE:
                if (j > i + 1 || i < 1022)   // 完整一轮的比较仍未结束，或者后面还有新的一轮比较需要进行
                    next_state = S_READ;
                else                            // 比较完成
                    next_state = S_DONE;
            S_DONE: begin                       // 停在 DONE，直到 start 释放
                if (start)
                    next_state = S_DONE;
                else
                    next_state = S_IDLE;
            end
            default:    // 对于其它非法状态，直接跳转到 IDLE
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
