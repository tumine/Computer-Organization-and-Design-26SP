module top (
    input  wire clk,
    input  wire rst_n,
    output wire halt
);

    wire [31:0] pc;
    wire [31:0] inst;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_we;
    wire [31:0] mem_rdata;

    // 例化 CPU
    CPU u_cpu (
        .clk        (clk),
        .rst_n      (rst_n),
        .pc         (pc),
        .inst       (inst),
        .mem_addr   (mem_addr),
        .mem_wdata  (mem_wdata),
        .mem_we     (mem_we),
        .mem_rdata  (mem_rdata),
        .halt       (halt)
    );

    // 例化指令内存（32x1024）
    inst_mem u_inst_mem (
        .a      (pc[11:2]),     // 抹除末两位对齐到字
        .spo    (inst)          // 异步读出
    );

    // 例化数据内存（4x8x1024，以实现字节级别掩码写入）
    wire [7:0] dout0, dout1, dout2, dout3;
    
    // 拼接成 32-bit 读数据
    assign mem_rdata = {dout3, dout2, dout1, dout0};

    data_mem_0 u_data_mem_0 (
        .a      (mem_addr[11:2]),
        .d      (mem_wdata[7:0]),
        .clk    (clk),
        .we     (mem_we[0]),
        .spo    (dout0)
    );

    data_mem_1 u_data_mem_1 (
        .a      (mem_addr[11:2]),
        .d      (mem_wdata[15:8]),
        .clk    (clk),
        .we     (mem_we[1]),
        .spo    (dout1)
    );

    data_mem_2 u_data_mem_2 (
        .a      (mem_addr[11:2]),
        .d      (mem_wdata[23:16]),
        .clk    (clk),
        .we     (mem_we[2]),
        .spo    (dout2)
    );

    data_mem_3 u_data_mem_3 (
        .a      (mem_addr[11:2]),
        .d      (mem_wdata[31:24]),
        .clk    (clk),
        .we     (mem_we[3]),
        .spo    (dout3)
    );

endmodule
