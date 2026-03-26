`timescale 1ns / 1ps

module Top3_ipb_tb;

    // Inputs
    reg clk;
    reg rstn;
    reg start;
    reg mode;
    reg [9:0] addr;

    // Outputs
    wire [7:0] an;
    wire [6:0] data;
    wire done;
    wire [15:0] count;

    // Instantiate the Unit Under Test (UUT)
    Top3_ipb uut (
        .clk(clk),
        .rstn(rstn),
        .start(start),
        .mode(mode),
        .addr(addr),
        .an(an),
        .data(data),
        .done(done),
        .count(count)
    );

    // Clock generation: 100MHz clock
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Stimulus process
    initial begin
        // Initialize Inputs
        rstn = 0;
        start = 0;
        mode = 1; // 1 for ascending, 0 for descending
        addr = 0;

        // Wait for global reset to finish
        #100;
        rstn = 1;
        #100;

        // Start sorting
        start = 1;
        #10;
        start = 0;

        // Wait for sorting to complete
        wait(done == 1'b1);
        #100;

        // Check sorted values by changing address
        addr = 10'd0;
        #200;
        
        addr = 10'd1;
        #200;

        addr = 10'd2;
        #200;

        addr = 10'd1023;
        #200;

        $finish;
    end

    // Optional: Monitor output
    initial begin
        $monitor("Time=%0t | rstn=%b | start=%b | mode=%b | addr=%d | done=%b | count=%d | an=%b | data=%b",
                 $time, rstn, start, mode, addr, done, count, an, data);
    end

endmodule