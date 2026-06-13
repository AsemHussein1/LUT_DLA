// True Dual-Port BRAM Module
`timescale 1ns / 1ps

module tdp_sram #(
    parameter DEPTH   = 4096,              // Number of entries
    parameter DATA_W  = 8,                 // Data width per entry
    parameter ADDR_W  = $clog2(DEPTH)      // Address width
)(
    // Port A: Write-only 
    input wire clk_a,
    input wire we_a,                    // Write enable
    input wire [ADDR_W-1:0] waddr_a,    // Write address
    input wire [DATA_W-1:0] wdata_a,    // Write data

    // Port B: Read-only 
    input wire clk_b,
    input wire re_b,                    // Read enable
    input wire [ADDR_W-1:0] raddr_b,    // Read address
    output reg [DATA_W-1:0] rdata_b     // Read data
);

    // BRAM Inference (Xilinx Synthesis Attributes)
    (* ram_style = "block" *) reg [DATA_W-1:0] mem [0:DEPTH-1];
    
    // Port A: Write Logic (synchronous write)
    always @(posedge clk_a) begin
        if (we_a) begin
            mem[waddr_a] <= wdata_a;
        end
    end

    // Port B: Read Logic (synchronous read with enable)
    always @(posedge clk_b) begin
        if (re_b) begin
            rdata_b <= mem[raddr_b];
        end
        // Note: Data retains previous value when re_b is LOW (no read)
    end

    // Optional: Initialize memory to zero (for simulation)
    //integer i;
    //initial begin
    //    for (i = 0; i < DEPTH; i = i + 1) begin
    //        mem[i] = {DATA_W{1'b0}};
    //    end
    //end

endmodule