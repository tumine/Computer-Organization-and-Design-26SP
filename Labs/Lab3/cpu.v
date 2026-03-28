module cpu (
    input  wire        clk,
    input  wire        rst_n,
    
    // 指令内存接口
    output wire [31:0] pc,
    input  wire [31:0] inst,
    
    // 数据内存接口
    output wire [31:0] mem_addr,
    output wire [31:0] mem_wdata,
    output wire [3:0]  mem_we,      // 写使能掩码
    input  wire [31:0] mem_rdata,
    
    // ebreak 停止信号
    output wire        halt
);

    // --- 内部信号声明 ---
    wire [31:0] next_pc;            // 用于跳转指令重置 PC
    wire [31:0] pc_plus_4 = pc + 4; // PC 缺省跳转到下一条指令地址
    
    // 具有固定域的各个参数，但不一定适用于当前指令
    wire [4:0]  rs1 = inst[19:15];
    wire [4:0]  rs2 = inst[24:20];
    wire [4:0]  rd  = inst[11:7];
    wire [2:0]  funct3 = inst[14:12];
    wire [6:0]  funct7 = inst[31:25];
    wire [6:0]  opcode = inst[6:0];

    wire [31:0] imm;
    wire [31:0] rf_rdata1, rf_rdata2, rf_wdata;
    wire [31:0] alu_out;
    wire        cmp_res;
    
    // 控制信号
    wire        pc_sel;      // 0: PC+4, 1: ALU/Branch target
    wire        rf_we;
    wire [1:0]  wb_sel;      // 00: ALU, 01: Mem, 10: PC+4
    wire        alu_src_a;   // 0: rs1, 1: PC
    wire        alu_src_b;   // 0: rs2, 1: imm
    wire [4:0]  alu_op;      // ALU 操作控制
    wire [2:0]  cmp_op;      // 比较器操作控制
    wire        mem_write;
    wire        mem_read;

    // --- PC 寄存器 ---
    reg [31:0] pc_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)      pc_reg <= 32'h0000_0000;   // 此处的重置值在必要时需要按照具体实现确定
        else if (!halt)  pc_reg <= next_pc; // 遇到 ebreak 则停止更新 PC
    end
    assign pc = pc_reg;
    assign next_pc = pc_sel ? alu_out : pc_plus_4; // 简化：JAL/Branch/JALR 目标统一由 ALU 计算或直接复用

    // --- 控制单元 ---
    decoder u_decoder (
        .opcode     (opcode),
        .funct3     (funct3),
        .funct7     (funct7),
        .cmp_res    (cmp_res),
        .pc_sel     (pc_sel),
        .rf_we      (rf_we),
        .wb_sel     (wb_sel),
        .alu_src_a  (alu_src_a),
        .alu_src_b  (alu_src_b),
        .alu_op     (alu_op),
        .cmp_op     (cmp_op),
        .mem_write  (mem_write),
        .mem_read   (mem_read),
        .halt       (halt)
    );

    // --- 寄存器堆 ---
    regfile u_regfile (
        .clk        (clk),
        .we         (rf_we),
        .rs1        (rs1),
        .rs2        (rs2),
        .rd         (rd),
        .wdata      (rf_wdata),
        .rdata1     (rf_rdata1),
        .rdata2     (rf_rdata2)
    );

    // --- 立即数生成 ---
    imm_gen u_imm_gen (
        .inst       (inst),
        .imm        (imm)
    );

    // --- ALU ---
    wire [31:0] alu_in_a = alu_src_a ? pc : rf_rdata1;
    wire [31:0] alu_in_b = alu_src_b ? imm : rf_rdata2;
    
    alu u_alu (
        .a          (alu_in_a),
        .b          (alu_in_b),
        .op         (alu_op),
        .out        (alu_out)
    );

    // --- 比较器 ---
    cmp u_cmp (
        .a          (rf_rdata1),
        .b          (rf_rdata2),
        .op         (cmp_op),
        .res        (cmp_res)
    );

    // --- 访存控制 ---
    wire [31:0] mem_read_data_processed;
    data_mem_ctrl u_data_mem_ctrl (
        .addr       (alu_out),
        .funct3     (funct3),
        .mem_write  (mem_write),
        .mem_read   (mem_read),
        .wdata_in   (rf_rdata2),
        .rdata_in   (mem_rdata),
        .wdata_out  (mem_wdata),
        .we_mask    (mem_we),
        .rdata_out  (mem_read_data_processed)
    );

    assign mem_addr = {alu_out[31:2], 2'b00}; // 强制地址对齐，偏移量由 mem_ctrl 处理

    // --- 写回选择 ---
    assign rf_wdata = (wb_sel == 2'b00) ? alu_out :
                      (wb_sel == 2'b01) ? mem_read_data_processed :
                      (wb_sel == 2'b10) ? pc_plus_4 : 32'b0;

endmodule
