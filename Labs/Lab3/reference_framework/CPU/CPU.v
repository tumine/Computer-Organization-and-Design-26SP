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

    input                   [ 4 : 0]            debug_reg_ra,   // TODO
    output                  [31 : 0]            debug_reg_rd    // TODO
);

    // Commit
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

    // Commit
    always @(posedge clk) begin
        if (rst) begin
            commit_reg          <= 1'B0;
            commit_pc_reg       <= 32'H0;
            commit_instr_reg    <= 32'H0;
            commit_halt_reg     <= 1'B0;
            commit_reg_we_reg   <= 1'B0;
            commit_reg_wa_reg   <= 5'H0;
            commit_reg_wd_reg   <= 32'H0;
            commit_dmem_we_reg  <= 1'B0;
            commit_dmem_wa_reg  <= 32'H0;
            commit_dmem_wd_reg  <= 32'H0;
        end
        else if (global_en) begin
            commit_reg          <= 1'B1;
            commit_pc_reg       <= 0;   // TODO
            commit_instr_reg    <= 0;   // TODO
            commit_halt_reg     <= 0;   // TODO
            commit_reg_we_reg   <= 0;   // TODO
            commit_reg_wa_reg   <= 0;   // TODO
            commit_reg_wd_reg   <= 0;   // TODO
            commit_dmem_we_reg  <= 0;   // TODO
            commit_dmem_wa_reg  <= 0;   // TODO
            commit_dmem_wd_reg  <= 0;   // TODO
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