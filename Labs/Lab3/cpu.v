module CPU (
    input  wire                   clk,
    input  wire                   rst,        // 高电平复位
    input  wire                   global_en,  // PDU 状态更新使能信号

    /* ------------------------------ Memory (inst) ----------------------------- */
    output wire [31 : 0]            imem_raddr,
    input  wire [31 : 0]            imem_rdata,

    /* ------------------------------ Memory (data) ----------------------------- */
    input  wire [31 : 0]            dmem_rdata,
    output wire [ 3 : 0]            dmem_we,    // 保持4位子存储器掩码配置
    output wire [31 : 0]            dmem_addr,
    output wire [31 : 0]            dmem_wdata,

    /* ---------------------------------- Debug --------------------------------- */
    output wire [ 0 : 0]            commit,
    output wire [31 : 0]            commit_pc,
    output wire [31 : 0]            commit_instr,
    output wire [ 0 : 0]            commit_halt,
    output wire [ 0 : 0]            commit_reg_we,
    output wire [ 4 : 0]            commit_reg_wa,
    output wire [31 : 0]            commit_reg_wd,
    output wire [ 0 : 0]            commit_dmem_we,
    output wire [31 : 0]            commit_dmem_wa,
    output wire [31 : 0]            commit_dmem_wd,

    input  wire [ 4 : 0]            debug_reg_ra,
    output wire [31 : 0]            debug_reg_rd
);

    wire [31:0] pc;
    wire [31:0] inst = imem_rdata;
    wire        halt;

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
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pc_reg <= 32'h0040_0000;
        end else if (global_en && !halt) begin
            pc_reg <= next_pc; 
        end
    end
    assign pc = pc_reg;
    assign imem_raddr = pc;
    assign next_pc = pc_sel ? alu_out : pc_plus_4; 

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
        .we         (rf_we && global_en && !halt), // 当 global_en 有效才允许写寄存器堆，避免PDU挂起时导致状态不断更新
        .rs1        (rs1),
        .rs2        (rs2),
        .rd         (rd),
        .wdata      (rf_wdata),
        .rdata1     (rf_rdata1),
        .rdata2     (rf_rdata2),
        .debug_ra   (debug_reg_ra),
        .debug_rd   (debug_reg_rd)
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

    // --- 访存控制与数据拼接 ---
    wire [31:0] mem_read_data_processed;
    data_mem_ctrl u_data_mem_ctrl (
        .addr       (alu_out),
        .funct3     (funct3),
        .mem_write  (mem_write),
        .mem_read   (mem_read),
        .wdata_in   (rf_rdata2),
        .rdata_in   (dmem_rdata),
        .wdata_out  (dmem_wdata),
        .we_mask    (dmem_we),
        .rdata_out  (mem_read_data_processed)
    );

    assign dmem_addr = {alu_out[31:2], 2'b00}; 

    // --- 写回选择 ---
    assign rf_wdata = (wb_sel == 2'b00) ? alu_out :
                      (wb_sel == 2'b01) ? mem_read_data_processed :
                      (wb_sel == 2'b10) ? pc_plus_4 : 32'b0;

    // --- Commit (Debug) 信号产生逻辑 ---
    reg  [ 0 : 0]   commit_reg          ;
    reg  [31 : 0]   commit_pc_reg       ;
    reg  [31 : 0]   commit_instr_reg    ;
    reg  [ 0 : 0]   commit_halt_reg     ;
    reg  [ 0 : 0]   commit_reg_we_reg   ;
    reg  [ 4 : 0]   commit_reg_wa_reg   ;
    reg  [31 : 0]   commit_reg_wd_reg   ;
    reg  [ 0 : 0]   commit_dmem_we_reg  ;
    reg  [31 : 0]   commit_dmem_wa_reg  ;
    reg  [31 : 0]   commit_dmem_wd_reg  ;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            commit_reg          <= 1'b0;
            commit_pc_reg       <= 32'b0;
            commit_instr_reg    <= 32'b0;
            commit_halt_reg     <= 1'b0;
            commit_reg_we_reg   <= 1'b0;
            commit_reg_wa_reg   <= 5'b0;
            commit_reg_wd_reg   <= 32'b0;
            commit_dmem_we_reg  <= 1'b0;
            commit_dmem_wa_reg  <= 32'b0;
            commit_dmem_wd_reg  <= 32'b0;
        end
        else if (global_en) begin
            commit_reg          <= 1'b1;
            commit_pc_reg       <= pc;
            commit_instr_reg    <= inst;
            commit_halt_reg     <= halt;
            commit_reg_we_reg   <= rf_we && (rd != 5'b0); // 只有不是 r0 且 we 有效时才是真正的写
            commit_reg_wa_reg   <= rd;
            commit_reg_wd_reg   <= rf_wdata;
            commit_dmem_we_reg  <= (|dmem_we); // |dmem_we 代表有内存写操作
            commit_dmem_wa_reg  <= {alu_out[31:2], 2'b00}; // 对齐后的地址
            commit_dmem_wd_reg  <= dmem_wdata;
        end
        else begin
            commit_reg <= 1'b0;
        end
    end

    assign commit           = commit_reg;
    assign commit_pc        = commit_pc_reg;
    assign commit_instr     = commit_instr_reg;
    assign commit_halt      = commit_halt_reg;
    assign commit_reg_we    = commit_reg_we_reg;
    assign commit_reg_wa    = commit_reg_wa_reg;
    assign commit_reg_wd    = commit_reg_wd_reg;
    assign commit_dmem_we   = commit_dmem_we_reg;
    assign commit_dmem_wa   = commit_dmem_wa_reg;
    assign commit_dmem_wd   = commit_dmem_wd_reg;

endmodule
