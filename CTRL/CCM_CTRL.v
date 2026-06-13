// ============================================================================
// CCM Controller Module (Updated)
// Orchestrates interaction between Input Buffers, Centroid Buffers, and CCU
// Now supports nested looping: N iterations over NUM_SUBSPACES subspaces
// Example: NUM_SUBSPACES=3, N=2 → processes subspaces in order: 0,1,2,0,1,2
// ============================================================================

module ccm_controller #(
    parameter N = 16,                  // Number of output matrix columns (N)
    parameter NUM_SUBSPACES = 16,      // Number of subspaces (Nc)
    parameter NUM_INPUTS = 16,         // Number of input vectors (M)
    parameter NUM_CENTROIDS = 16,      // Number of centroids (C)
    parameter ISRAM_ADDR_WIDTH = 10,   // Input SRAM address width
    parameter CSRAM_ADDR_WIDTH = 10    // Centroid SRAM address width
) (
    input wire clk,
    input wire rst_n,
    
    // Start signal
    input wire ccm_start_pulse,
    
    // Input Buffer interface
    output reg [ISRAM_ADDR_WIDTH-1:0] ctrl2ib_start_addr,
    output reg ctrl2ib_valid,
    input wire ib2ctrl_ready,
    
    // Centroid Buffer interface
    output reg [CSRAM_ADDR_WIDTH-1:0] ctrl2cb_start_addr,
    output reg ctrl2cb_valid,
    input wire cb2ctrl_ready,
    
    // CCU interface
    input wire ccu_done,
    
    // Done signal
    output reg ccm_done_pulse
);

    // ========================================================================
    // State Machine Definitions
    // ========================================================================
    localparam IDLE   = 2'b00;
    localparam ACTIVE = 2'b01;
    localparam DONE   = 2'b10;
    
    reg [1:0] current_state, next_state;
    
    // ========================================================================
    // Internal Counters
    // ========================================================================
    localparam SUBSPACE_COUNTER_WIDTH = $clog2(NUM_SUBSPACES);
    localparam N_COUNTER_WIDTH = $clog2(N);
    localparam TOTAL_COUNTER_WIDTH = $clog2(NUM_SUBSPACES * N);
    
    reg [SUBSPACE_COUNTER_WIDTH-1:0] ib_addr_count;   // Input buffer subspace counter (0 to NUM_SUBSPACES-1)
    reg [SUBSPACE_COUNTER_WIDTH-1:0] cb_addr_count;   // Centroid buffer subspace counter (0 to NUM_SUBSPACES-1)
    
    reg [N_COUNTER_WIDTH-1:0] ib_n_loop_count;           // Input buffer outer loop counter (0 to N-1)
    reg [N_COUNTER_WIDTH-1:0] cb_n_loop_count;           // Centroid buffer outer loop counter (0 to N-1)
    reg [TOTAL_COUNTER_WIDTH:0] total_count;           // Total completion counter (counts ccu_done pulses)
    
    // Total number of operations = NUM_SUBSPACES * N
    localparam TOTAL_OPERATIONS = NUM_SUBSPACES * N;
    
    // ========================================================================
    // Handshake Detection Signals
    // ========================================================================
    wire ib_handshake = ctrl2ib_valid && ib2ctrl_ready;
    wire cb_handshake = ctrl2cb_valid && cb2ctrl_ready;
    
    // ========================================================================
    // Current State Logic
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end
    
    // ========================================================================
    // Next State Logic
    // ========================================================================
    always @(*) begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (ccm_start_pulse) begin
                    next_state = ACTIVE;
                end
            end
            ACTIVE: begin
                // Complete when all N*NUM_SUBSPACES operations are done
                if (total_count >= TOTAL_OPERATIONS) begin
                    next_state = DONE;
                end
            end
            DONE: begin
                next_state = IDLE;
            end
            default: begin
                next_state = IDLE;
            end
        endcase
    end
    
    // ========================================================================
    // Counters Logic
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            total_count <= 0;
            cb_addr_count <= 0;
            ib_addr_count <= 0;
            ib_n_loop_count <= 0;
            cb_n_loop_count <= 0;
        end else begin
            case (current_state)
                IDLE: begin
                    total_count <= 0;
                    cb_addr_count <= 0;
                    ib_addr_count <= 0;
                    ib_n_loop_count <= 0;
                    cb_n_loop_count <= 0;
                end
                
                ACTIVE: begin
                    // Count total CCU completions
                    if (ccu_done) begin
                        total_count <= total_count + 1;
                    end
                    
                    // Centroid buffer counter with wrapping
                    if (cb_handshake) begin
                        if (cb_addr_count < NUM_SUBSPACES - 1) begin
                            cb_addr_count <= cb_addr_count + 1;
                        end else begin
                            // Wrap around to 0 after reaching last subspace
                            cb_addr_count <= 0;
                            // Increment outer loop counter when wrapping
                            if (cb_n_loop_count < N - 1) begin
                                cb_n_loop_count <= cb_n_loop_count + 1;
                            end
                        end
                    end
                    
                    // Input buffer counter with wrapping
                    if (ib_handshake) begin
                        if (ib_addr_count < NUM_SUBSPACES - 1) begin
                            ib_addr_count <= ib_addr_count + 1;
                        end else begin
                            // Wrap around to 0 after reaching last subspace
                            ib_addr_count <= 0;
                            // Increment outer loop counter when wrapping
                            if (ib_n_loop_count < N - 1) begin
                                ib_n_loop_count <= ib_n_loop_count + 1;
                            end
                        end
                    end
                end
                
                DONE: begin
                    total_count <= 0;
                    cb_addr_count <= 0;
                    ib_addr_count <= 0;
                    ib_n_loop_count <= 0;
                    cb_n_loop_count <= 0;
                end
            endcase
        end
    end
    
    // ========================================================================
    // Input Buffer Valid Signal and Start Address
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl2ib_valid <= 1'b0;
            ctrl2ib_start_addr <= 0;
        end else begin
            case (current_state)
                IDLE: begin
                    ctrl2ib_start_addr <= 0;
                    if (ccm_start_pulse) begin
                        ctrl2ib_valid <= 1'b1;
                    end else begin
                        ctrl2ib_valid <= 1'b0;
                    end
                end
                
                ACTIVE: begin
                    // Update address on handshake
                    if (ib_handshake) begin
                        // Calculate next address based on next counter value
                        if (ib_addr_count < NUM_SUBSPACES - 1) begin
                            // Next subspace in sequence
                            ctrl2ib_start_addr <= (ib_addr_count + 1) * NUM_INPUTS;
                        end else begin
                            // Wrap to first subspace
                            ctrl2ib_start_addr <= 0;
                        end
                    end
                    
                    // Deassert valid when all operations complete
                    // Check if we've sent addresses for all N*NUM_SUBSPACES operations
                    if (ib_handshake) begin
                        // Calculate total handshakes that will have occurred
                        if ((ib_n_loop_count == N - 1) && (ib_addr_count == NUM_SUBSPACES - 1)) begin
                            ctrl2ib_valid <= 1'b0;
                        end
                    end
                end
                
                DONE: begin
                    ctrl2ib_valid <= 1'b0;
                    ctrl2ib_start_addr <= 0;
                end
            endcase
        end
    end
    
    // ========================================================================
    // Centroid Buffer Valid Signal and Start Address
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl2cb_valid <= 1'b0;
            ctrl2cb_start_addr <= 0;
        end else begin
            case (current_state)
                IDLE: begin
                    ctrl2cb_start_addr <= 0;
                    if (ccm_start_pulse) begin
                        ctrl2cb_valid <= 1'b1;
                    end else begin
                        ctrl2cb_valid <= 1'b0;
                    end
                end
                
                ACTIVE: begin
                    // Update address on handshake
                    if (cb_handshake) begin
                        // Calculate next address based on next counter value
                        if (cb_addr_count < NUM_SUBSPACES - 1) begin
                            // Next subspace in sequence
                            ctrl2cb_start_addr <= (cb_addr_count + 1) * NUM_CENTROIDS;
                        end else begin
                            // Wrap to first subspace
                            ctrl2cb_start_addr <= 0;
                        end
                    end
                    
                    // Deassert valid when all operations complete
                    // Check if we've sent addresses for all N*NUM_SUBSPACES operations
                    if (cb_handshake) begin
                        // Calculate total handshakes that will have occurred
                        if ((cb_n_loop_count == N - 1) && (cb_addr_count == NUM_SUBSPACES - 1)) begin
                            ctrl2cb_valid <= 1'b0;
                        end
                    end
                end
                
                DONE: begin
                    ctrl2cb_valid <= 1'b0;
                    ctrl2cb_start_addr <= 0;
                end
            endcase
        end
    end
    
    // ========================================================================
    // CCM Done Pulse Signal
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ccm_done_pulse <= 1'b0;
        end else if (current_state == ACTIVE && total_count >= TOTAL_OPERATIONS) begin
            ccm_done_pulse <= 1'b1;
        end else begin
            ccm_done_pulse <= 1'b0;
        end
    end

endmodule