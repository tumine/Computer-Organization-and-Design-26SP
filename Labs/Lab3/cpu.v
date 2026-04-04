`ifndef INSTR_MEM_START
  `define INSTR_MEM_START 32'H00400000
`endif
`ifndef INSTR_MEM_DEPTH
  `define INSTR_MEM_DEPTH 16
`endif
`ifndef DATA_MEM_START
  `define DATA_MEM_START 32'H10010000
`endif
`ifndef DATA_MEM_DEPTH
  `define DATA_MEM_DEPTH 16
`endif

module CPU (
    input                   [ 0 : 0]            clk,
    input                   [ 0 : 0]            rst,
    input                   [ 0 : 0]            global_en,

/* ------------------------------ Memory (inst) ----------------------------- */
    output                  [31 : 0]            imem_raddr,
    input                   [31 : 0]            imem_rdata,

/* ------------------------------ Memory (data) ----------------------------- */
    input                   [31 : 0]            dmem_rdata,
    output                  [ 0 : 0]            dmem_we,
    output                  [31 : 0]            dmem_addr,
    output                  [31 : 0]            dmem_wdata,

/* ---------------------------------- Debug --------------------------------- */
    output                  [ 0 : 0]            commit,
    output                  [31 : 0]            commit_pc,
    output                  [31 : 0]            commit_instr,
    output                  [ 0 : 0]            commit_halt,
    output                  [ 0 : 0]            commit_reg_we,
    output                  [ 4 : 0]            commit_reg_wa,
    output                  [31 : 0]            commit_reg_wd,
    output                  [ 0 : 0]            commit_dmem_we,
    output                  [31 : 0]            commit_dmem_wa,
    output                  [31 : 0]            commit_dmem_wd,

    input                   [ 4 : 0]            debug_reg_ra,
    output                  [31 : 0]            debug_reg_rd
);

    // ========================= PC 与指令提取 =========================
    wire [31:0] pc;
    // 越界保护：PC 超出指令存储器范围时将指令置为 NOP
    wire        mem_out_bounds = (pc < `INSTR_MEM_START)
                              || (pc >= `INSTR_MEM_START + (1 << (`INSTR_MEM_DEPTH + 2)));
    wire [31:0] inst = mem_out_bounds ? 32'b0 : imem_rdata;
    wire        halt;

    // 内部信号
    wire [31:0] next_pc;
    wire [31:0] pc_plus_4 = pc + 4;

    // 指令字段提取
    wire [4:0]  rs1     = inst[19:15];
    wire [4:0]  rs2     = inst[24:20];
    wire [4:0]  rd      = inst[11:7];
    wire [2:0]  funct3  = inst[14:12];
    wire [6:0]  funct7  = inst[31:25];
    wire [6:0]  opcode  = inst[6:0];

    wire [31:0] imm;
    wire [31:0] rf_rdata1, rf_rdata2, rf_wdata;
    wire [31:0] alu_out;
    wire        cmp_res;

    // 控制信号
    wire        pc_sel;
    wire        rf_we;
    wire [1:0]  wb_sel;
    wire        alu_src_a;
    wire        alu_src_b;
    wire [4:0]  alu_op;
    wire [2:0]  cmp_op;
    wire        mem_write;
    wire        mem_read;
    wire        is_jalr;

    // ========================= PC 寄存器 =========================
    reg [31:0] pc_reg;
    always @(posedge clk) begin
        if (rst) begin
            pc_reg <= `INSTR_MEM_START;
        end
        else if (global_en && !halt) begin
            pc_reg <= next_pc;
        end
    end
    assign pc = pc_reg;
    assign imem_raddr = pc;

    // JALR 跳转目标需要将 LSB 清零：target = (rs1 + imm) & ~1
    // 其他跳转指令直接使用 ALU 输出
    assign next_pc = pc_sel ? (is_jalr ? {alu_out[31:1], 1'b0} : alu_out)
                            : pc_plus_4;

    // ========================= 控制单元（译码器） =========================
    decoder u_decoder (
        .opcode     (opcode),
        .funct3     (funct3),
        .funct7     (funct7),
        .cmp_res    (cmp_res),
        .inst20     (inst[20]),

        .pc_sel     (pc_sel),
        .rf_we      (rf_we),
        .wb_sel     (wb_sel),
        .alu_src_a  (alu_src_a),
        .alu_src_b  (alu_src_b),
        .alu_op     (alu_op),
        .cmp_op     (cmp_op),
        .mem_write  (mem_write),
        .mem_read   (mem_read),
        .is_jalr    (is_jalr),
        .halt       (halt)
    );

    // ========================= 寄存器堆 =========================
    regfile u_regfile (
        .clk        (clk),
        .we         (rf_we && global_en && !halt),
        .rs1        (rs1),
        .rs2        (rs2),
        .rd         (rd),
        .wdata      (rf_wdata),
        .rdata1     (rf_rdata1),
        .rdata2     (rf_rdata2),
        .debug_ra   (debug_reg_ra),
        .debug_rd   (debug_reg_rd)
    );

    // ========================= 立即数生成 =========================
    imm_gen u_imm_gen (
        .inst       (inst),
        .imm        (imm)
    );

    // ========================= ALU =========================
    wire [31:0] alu_in_a = alu_src_a ? pc : rf_rdata1;
    wire [31:0] alu_in_b = alu_src_b ? imm : rf_rdata2;

    alu u_alu (
        .a          (alu_in_a),
        .b          (alu_in_b),
        .op         (alu_op),
        .out        (alu_out)
    );

    // ========================= 分支比较器 =========================
    cmp u_cmp (
        .a          (rf_rdata1),
        .b          (rf_rdata2),
        .op         (cmp_op),
        .res        (cmp_res)
    );

    // ========================= 数据存储器访问控制 =========================
    wire [31:0] mem_read_data_processed;
    wire [31:0] ctrl_wdata;
    wire [ 3:0] ctrl_we_mask;

    data_mem_ctrl u_data_mem_ctrl (
        .addr       (alu_out),
        .funct3     (funct3),
        .mem_write  (mem_write),
        .mem_read   (mem_read),
        .wdata_in   (rf_rdata2),
        .rdata_in   (dmem_rdata),
        .wdata_out  (ctrl_wdata),
        .we_mask    (ctrl_we_mask),
        .rdata_out  (mem_read_data_processed)
    );

    // 数据存储器地址字对齐（低 2 位清零）
    assign dmem_addr = {alu_out[31:2], 2'b00};

    // 直接输出由 data_mem_ctrl 已经 RMW 合并好的写数据
    assign dmem_wdata = ctrl_wdata;

    // 至少有 1 个字节写入有效时置写使能
    assign dmem_we = mem_write && (|ctrl_we_mask) && global_en;

    // ========================= 写回选择 =========================
    assign rf_wdata = (wb_sel == 2'b00) ? alu_out :
                      (wb_sel == 2'b01) ? mem_read_data_processed :
                      (wb_sel == 2'b10) ? pc_plus_4 : 32'b0;

    // ========================= Commit（调试信号） =========================
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

    always @(posedge clk) begin
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
            commit_reg_we_reg   <= rf_we;
            commit_reg_wa_reg   <= rd;
            commit_reg_wd_reg   <= (rd == 5'b0) ? 32'b0 : rf_wdata;
            commit_dmem_we_reg  <= (mem_write && (|ctrl_we_mask));
            commit_dmem_wa_reg  <= (mem_read || mem_write) ? dmem_addr : `DATA_MEM_START;
            commit_dmem_wd_reg  <= (mem_write && (|ctrl_we_mask)) ? dmem_wdata : 32'b0;
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