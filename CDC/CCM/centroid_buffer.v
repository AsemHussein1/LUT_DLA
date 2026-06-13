module centroid_buffer #(
    parameter NUM_CENTROIDS = 16,   // number of centroids
    parameter VECTOR_LENGTH = 2,    // number of values per centroid/vector
    parameter CENTROID_VALUE_WIDTH = 8,   // number of bits in a single value
    parameter CENTROID_ADDR_WIDTH = $clog2(NUM_CENTROIDS), // number of bits to count the centroids = log2(NUM_CENTROIDS)
    parameter CSRAM_ADDR_WIDTH = 10   // number of bits in the address of the centroid memory
) (
    // General signals
    input clk,
    input rst_n,

    // Controller signals
    input [CSRAM_ADDR_WIDTH-1:0] ctrl2cb_start_addr,
    input ctrl2cb_addr_valid,
    output reg cb2ctrl_addr_ready,

    // Port b CSRAM memory signals
    output reg cb2csb_re,                          // Read enable
    output reg [CSRAM_ADDR_WIDTH-1:0] cb2csb_addr,   // Read address
    input [CENTROID_VALUE_WIDTH*VECTOR_LENGTH-1:0] csb2cb_data,  // Read data from SRAM

    // CCU signals
    input ccu2cb_ready,
    output reg [NUM_CENTROIDS*CENTROID_VALUE_WIDTH*VECTOR_LENGTH-1:0] cb2ccu_centroids,
    output reg cb2ccu_valid
    
);

    // States
    localparam IDLE = 2'b00;
    localparam READ = 2'b01;
    localparam SEND = 2'b10;

    // Internal signals
    reg [1:0] cs, ns;

    reg [CENTROID_ADDR_WIDTH-1:0] data_count, addr_count;
    reg [CSRAM_ADDR_WIDTH-1:0] base_addr;
    reg read_active;

    // State Memory and Output Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // reset
            cs <= IDLE;
            
            cb2ctrl_addr_ready <= 1;

            cb2csb_re <= 0;
            cb2csb_addr <= 0;
            read_active <= 0;

            cb2ccu_centroids <= 0;
            cb2ccu_valid <= 0;

            data_count <= 0;
            addr_count <= 0;
            base_addr <= 0;
        end
        else begin
            cs <= ns;

            case (cs)
                IDLE: begin
                    cb2ccu_centroids <= 0;
                    cb2ccu_valid <= 0;

                    addr_count <= 0;
                    data_count <= 0;

                    if (cb2ctrl_addr_ready && ctrl2cb_addr_valid) begin
                        cb2ctrl_addr_ready <= 0;
                        base_addr <= ctrl2cb_start_addr;
                        cb2csb_addr <= ctrl2cb_start_addr;
                        cb2csb_re <= 1;
                        read_active <= 1;

                    end else begin
                        cb2ctrl_addr_ready <= 1;
                        base_addr <= 0;
                        cb2csb_re <= 0;
                        cb2csb_addr <= 0;
                        read_active <= 0;
                        
                    end
                end
                READ: begin
                    // Address generation logic
                    if (read_active) begin
                        if (addr_count < NUM_CENTROIDS - 1) begin  
                            addr_count <= addr_count + 1;
                            cb2csb_addr <= base_addr + addr_count +1;
                            cb2csb_re <=1;
                        end else begin
                            cb2csb_addr <= 0;
                            cb2csb_re <= 0;
                            read_active <= 0;
                        end   
                    end 
                    // Data capture logic
                    if (addr_count > 0) begin
                        cb2ccu_centroids <= {csb2cb_data, cb2ccu_centroids[NUM_CENTROIDS*CENTROID_VALUE_WIDTH*VECTOR_LENGTH-1:CENTROID_VALUE_WIDTH*VECTOR_LENGTH]};
                        if (data_count < NUM_CENTROIDS-1)
                            data_count <= data_count + 1;
                    end
                end
                SEND: begin
                    cb2ccu_valid <= 1;
                    cb2ctrl_addr_ready <= 0;
                    cb2csb_addr <= 0;
                    cb2csb_re <= 0;
                end
            endcase
        end
    end

    // Next State Logic
    always @(*) begin
        ns = cs; // Default next state assignment
        case (cs)
            IDLE: 
                if (cb2ctrl_addr_ready && ctrl2cb_addr_valid) 
                    ns = READ;
            READ:
                if (data_count == NUM_CENTROIDS-1)
                    ns = SEND;
            SEND: 
                if (ccu2cb_ready && cb2ccu_valid)
                    ns = IDLE;
        endcase
    end

endmodule