module dPE #(
    parameter V_LEN  = 4,
    parameter BW     = 8,
    parameter IDX_BW = 8,
    parameter DPE_ID = 0,
    parameter IS_FIRST = 0,
    parameter IS_LAST  = 0,
    parameter DIST_BW = BW + $clog2(V_LEN)
)(
    input wire clk,
    input wire rst_n,

    input wire load_centroid,
    input wire ccu_ready,
    input wire enable,
    input wire [(V_LEN*BW)-1:0] in_vector_flat,
    input wire [DIST_BW-1:0] in_min_dist,
    input wire [IDX_BW-1:0] in_idx,
    input wire in_valid,
    input wire [(V_LEN*BW)-1:0] this_dpe_centroid_flat, 
    
    output reg [(V_LEN*BW)-1:0]out_vector_flat,
    output reg [DIST_BW-1:0] out_min_dist,
    output reg [IDX_BW-1:0] out_idx,
    output reg out_valid
);

    integer i;
    reg [DIST_BW-1:0] current_l1_dist;
    reg [BW-1:0]      element_diff;
    
    reg [(V_LEN*BW)-1:0] local_centroid_flat;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            local_centroid_flat <= 0;
        else if (load_centroid && ccu_ready) 
            local_centroid_flat <= this_dpe_centroid_flat;
    end

    always @(*) begin
        current_l1_dist = 0;
        for (i = 0; i < V_LEN; i = i + 1) begin
            if (in_vector_flat[i*BW +: BW] > local_centroid_flat[i*BW +: BW]) 
                element_diff = in_vector_flat[i*BW +: BW] - local_centroid_flat[i*BW +: BW];
            else
                element_diff = local_centroid_flat[i*BW +: BW] - in_vector_flat[i*BW +: BW];
            
            current_l1_dist = current_l1_dist + element_diff;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 0;
            out_idx <= 0;
            out_min_dist <= 0;
            out_vector_flat <= 0;
        end else if(enable) begin
            out_valid <= in_valid;
            out_idx   <= (IS_FIRST) ? DPE_ID : ((current_l1_dist < in_min_dist) ? DPE_ID : in_idx);

            if (!IS_LAST) begin
                out_vector_flat <= in_vector_flat;
                out_min_dist    <= (IS_FIRST) ? current_l1_dist : ((current_l1_dist < in_min_dist) ? current_l1_dist : in_min_dist);
            end
        end
    end
endmodule

module CCU #(
    parameter NUM_DPES = 4,
    parameter V_LEN    = 4,
    parameter BW       = 8,
    parameter IDX_BW   = 8,
    parameter M_ROWS   = 1024 
)(
    // General signals
    input wire clk,
    input wire rst_n,
    // Controller signals
    output reg ccu_done,
    // Input buffer signals
    input wire ib2ccu_valid,  
    input wire [(V_LEN*BW)-1:0] ib2ccu_ip_vector,
    output wire ccu2ib_ready,
    // Centroid buffer signals
    input wire cb2ccu_valid, 
    input wire [(BW*V_LEN*NUM_DPES)-1:0] cb2ccu_centroids,
    output reg ccu2cb_ready,
    // FIFO signals
    output wire ccu2fifo_valid,
    output wire [IDX_BW-1:0] ccu2fifo_idx,
    input wire fifo2ccu_ready    
);

    localparam DIST_BW = BW + $clog2(V_LEN);
    localparam M_BW    = $clog2(M_ROWS + 1);

    localparam IDLE = 1'b0;
    localparam ACTIVE = 1'b1;
    reg state;


    reg [M_BW-1:0] in_counter, out_counter;

    // FSM Control
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            in_counter <= 0;
            out_counter <= 0;
            ccu2cb_ready <= 1;
            ccu_done <= 0;
        end else begin
            ccu_done <= 1'b0;
            case (state)
                IDLE: begin
                    ccu2cb_ready <= 1;
                    in_counter <= 0;
                    out_counter <= 0;
                    if (cb2ccu_valid && ccu2cb_ready)
                        begin 
                            ccu2cb_ready <= 0;
                            state <= ACTIVE;
                        end
                end
                ACTIVE: begin

                    if (ib2ccu_valid && ccu2ib_ready && fifo2ccu_ready) begin
                        in_counter <= in_counter + 1;
                    end
                    
                    if (ccu2fifo_valid && fifo2ccu_ready) begin
                        if (out_counter == M_ROWS - 1)
                            begin
                                ccu_done <= 1;
                                state <= IDLE;
                            end
                        else out_counter <= out_counter + 1;
                    end
                end
            endcase
        end
    end

    // Pipeline Wires
    wire [(V_LEN*BW)-1:0] v_chain   [NUM_DPES:0];
    wire [DIST_BW-1:0]    d_chain   [NUM_DPES:0];
    wire [IDX_BW-1:0]     i_chain   [NUM_DPES:0];
    wire                  vld_chain [NUM_DPES:0];

    assign v_chain[0]   = ib2ccu_ip_vector;
    assign vld_chain[0] = ib2ccu_valid && ccu2ib_ready; //Gated against ready state
    assign d_chain[0]   = {DIST_BW{1'b1}};
    assign i_chain[0]   = 0;

    genvar g;
    generate
        for (g = 0; g < NUM_DPES; g = g + 1) begin : stages
            dPE #(
                .V_LEN(V_LEN), 
                .BW(BW),
                .IDX_BW(IDX_BW),
                .DPE_ID(g),
                .IS_FIRST(g == 0),
                .IS_LAST(g == NUM_DPES-1),
                .DIST_BW(DIST_BW)
            ) inst (
                .clk(clk),
                .rst_n(rst_n),
                .load_centroid(cb2ccu_valid),
                .enable(fifo2ccu_ready),
                .ccu_ready(ccu2cb_ready),
                .in_vector_flat(v_chain[g]),
                .in_min_dist(d_chain[g]), 
                .in_idx(i_chain[g]),
                .in_valid(vld_chain[g]),
                .this_dpe_centroid_flat(cb2ccu_centroids[g*V_LEN*BW +: V_LEN*BW]),
                .out_vector_flat(v_chain[g+1]),
                .out_min_dist(d_chain[g+1]), 
                .out_idx(i_chain[g+1]),
                .out_valid(vld_chain[g+1])
            );
        end
    endgenerate

    assign ccu2fifo_idx = i_chain[NUM_DPES];
    assign ccu2fifo_valid = vld_chain[NUM_DPES];
    assign ccu2ib_ready = (fifo2ccu_ready == 1 && in_counter < M_ROWS && state == ACTIVE) ? 1 : 0;

endmodule