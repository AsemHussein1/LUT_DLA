module PSUM_LUT #(
    parameter NUM_CENTROIDS = 16,                           // number of centroids=values needed from the LUT
    parameter MEM_ADDR_WIDTH = 10,                          // memory address bit size
    parameter VALUE_WIDTH = 8,                              // number of bits in a single value
    parameter INNER_LOOP_LIMIT = 20,                        // inner loop M (number of input rows)
    parameter CENTROID_ADDR_WIDTH = $clog2(NUM_CENTROIDS)   // number of bits to count the values obtained from LUT
)(
    // General input signals
    input wire clk,
    input wire rst_n,

    // Controller
    input wire [MEM_ADDR_WIDTH-1:0] ctrl2psum_start_addr,
    input wire ctrl2psum_addr_valid,
    output reg  psum2ctrl_addr_ready,

    // Memory
    input wire [VALUE_WIDTH-1:0] mem2psum_lut_value,
    output reg [MEM_ADDR_WIDTH-1:0] psum2mem_addr,
    output reg psum2mem_re,

    // FIFO 
    input wire fifo2psum_valid,
    input wire [CENTROID_ADDR_WIDTH-1:0] fifo2psum_index,
    output wire psum2fifo_ready,

    // Scratchpad 
    input wire spad2psum_ready,
    output reg psum2spad_valid,
    output reg [VALUE_WIDTH-1:0] psum2spad_value
);

    // Local parameters
    localparam INNER_LOOP_WIDTH = $clog2(INNER_LOOP_LIMIT + 1);
    localparam CENTROID_COUNT_WIDTH = $clog2(NUM_CENTROIDS + 1);
    integer i;

    // Ping Pong buffer banks
    reg [VALUE_WIDTH-1:0] Bank_0 [0:NUM_CENTROIDS-1];
    reg [VALUE_WIDTH-1:0] Bank_1 [0:NUM_CENTROIDS-1];

    // Internal control registers and counters
    reg [MEM_ADDR_WIDTH-1:0] base_addr;
    reg [CENTROID_COUNT_WIDTH-1:0] addr_count;
    reg [CENTROID_COUNT_WIDTH-1:0] value_count;
    reg [INNER_LOOP_WIDTH-1:0] consumer_count;

    reg ping_pong_select; 
    reg producer_done;
    reg consumer_done;
    reg re_pipe; 

    // ----- Producer Logic (Controller + Memory + Shadow Bank) -----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            base_addr <= 0;
            addr_count <= 0;
            value_count <= 0;
            producer_done <= 0;
            re_pipe <= 0;
            psum2mem_addr <= 0;
            psum2mem_re <= 0;
            psum2ctrl_addr_ready <= 1;  
        end else begin
            re_pipe <= psum2mem_re;
            
            if (ctrl2psum_addr_valid && psum2ctrl_addr_ready) begin
                base_addr <= ctrl2psum_start_addr;
                addr_count <= 0;
                value_count <= 0;
                producer_done <= 0;
                psum2ctrl_addr_ready <= 1'b0;
                psum2mem_addr <= ctrl2psum_start_addr;
                psum2mem_re <= 1'b1;
            end

            if (psum2mem_re) begin
                if (addr_count < NUM_CENTROIDS - 1) begin
                    addr_count <= addr_count + 1;
                    psum2mem_addr <= base_addr + addr_count + 1;
                end else begin 
                    psum2mem_re <= 1'b0;
                end
            end

            if (re_pipe) begin
                value_count <= value_count + 1;
                if (value_count == NUM_CENTROIDS - 1) begin 
                    producer_done <= 1'b1;
                end
            end

            if (producer_done && consumer_done) begin
                psum2ctrl_addr_ready <= 1'b1;
                producer_done <= 1'b0;
            end
        end
    end

    // Shadow Bank assignment
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_CENTROIDS; i = i + 1) begin
                Bank_0[i] <= 0;
                Bank_1[i] <= 0;
            end
        end else begin
            if (re_pipe) begin
                if (ping_pong_select == 1'b0)
                    Bank_1[value_count] <= mem2psum_lut_value;
                else
                    Bank_0[value_count] <= mem2psum_lut_value;
            end
        end
    end

    // ----- Consumer Logic (FIFO + Scratchpad + Active Bank) -----
    wire spad_ack = psum2spad_valid && spad2psum_ready;

    // FIX: Block FIFO ready on the very last accumulation clock cycle of the loop to protect Row 0
    assign psum2fifo_ready = !consumer_done && (!psum2spad_valid || spad2psum_ready) 
                             && !(spad_ack && (consumer_count == INNER_LOOP_LIMIT - 1));

    wire fifo_pop = psum2fifo_ready && fifo2psum_valid;

    // Output Data Pipeline
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            psum2spad_valid <= 1'b0;
            psum2spad_value <= 0;
            consumer_count <= 0;
            consumer_done <= 1'b1; 
            ping_pong_select <= 0;
        end else begin
            if (fifo_pop) begin
                psum2spad_valid <= 1'b1;
                psum2spad_value <= (ping_pong_select == 1'b0) ? Bank_0[fifo2psum_index] : Bank_1[fifo2psum_index];
            end else if (spad_ack) begin
                psum2spad_valid <= 1'b0;
            end

            if (spad_ack) begin
                if (consumer_count == INNER_LOOP_LIMIT - 1) begin
                    consumer_count <= 0;
                    consumer_done <= 1'b1;
                end else begin
                    consumer_count <= consumer_count + 1;
                end
            end

            if (producer_done && consumer_done) begin
                ping_pong_select <= ~ping_pong_select;
                consumer_done <= 1'b0;
            end
        end
    end

endmodule