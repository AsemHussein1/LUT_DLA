// =============================================================
//  IMM_CTRL — PSum LUT + Scratchpad Sequencer
//
//  Controls the In-Memory Matching phase.
//  Does NOT drive the CCU, Centroid Buffer, or Input Buffer —
//  those are exclusively managed by ccm_controller.
//
//  Run order (K×N pairs, concurrent with CCM):
//    For each column n (0..N-1):
//      For each subspace s (0..K-1):
//        1. Send LUT start address = s*(N*C) + n*C to PSumLUT
//        2. PSumLUT loads C values from LSRAM into shadow bank
//        3. PSumLUT drains M FIFO indices → pushes partial sums to Scratchpad
//        4. psum2ctrl_addr_ready re-asserts (pair done)
//        5. Advance to next (s, n) pair
//    After all K×N pairs:
//        6. Wait for Scratchpad to finish accumulation (spad2ctrl_addr_ready HIGH)
//        7. Deliver output base address to Scratchpad
//        8. Wait for Scratchpad streaming done (spad2ctrl_done)
//        9. Assert imm_done and return to IDLE
//
//  LUT address equation:
//    addr(s, n) = s * N * NUM_CENTROIDS + n * NUM_CENTROIDS
// =============================================================

module IMM_CTRL #(
    parameter NUM_CENTROIDS  = 16,          // C — centroids per subspace
    parameter MEM_ADDR_WIDTH = 10,          // address bus width for LUT and Scratchpad
    parameter N              = 16,          // output columns
    parameter K              = 16,          // number of subspaces

    // Derived — do not override
    parameter K_CNT_WIDTH    = $clog2(K + 1),
    parameter N_CNT_WIDTH    = $clog2(N + 1)
)(
    // ── Global ──────────────────────────────────────────────────
    input  wire                        clk,
    input  wire                        rst_n,

    // ── Runtime loop bounds ──────────────────────────────────────
    input  wire [K_CNT_WIDTH-1:0]      k_total,        // runtime subspaces per column (≤ K)
    input  wire [N_CNT_WIDTH-1:0]      n_total,        // runtime columns (≤ N)

    // ── Top-level kick ──────────────────────────────────────────
    input  wire                        top2imm_valid,  // 1-cycle start pulse
    output reg                         imm2top_ready,  // CTRL idle
    output reg                         imm_done,       // computation complete (1-cycle pulse)

    // ── Scratchpad output base address ───────────────────────────
    input  wire [MEM_ADDR_WIDTH-1:0]   spad_out_addr,  // output SRAM base (sent once)

    // ── PSum LUT interface ───────────────────────────────────────
    output reg  [MEM_ADDR_WIDTH-1:0]   ctrl2psum_start_addr,  // LUT base for this pair
    output reg                         ctrl2psum_addr_valid,   // address valid
    input  wire                        psum2ctrl_addr_ready,   // ready / pair-done

    // ── Scratchpad interface ─────────────────────────────────────
    output reg  [MEM_ADDR_WIDTH-1:0]   ctrl2spad_start_addr,  // output SRAM base
    output reg                         ctrl2spad_addr_valid,   // address valid
    input  wire                        spad2ctrl_addr_ready,   // Scratchpad ready for addr
    input  wire                        spad2ctrl_done          // Scratchpad streaming done
);

    // =========================================================
    //  FSM State Encoding
    // =========================================================
    localparam [2:0]
        S_IDLE        = 3'd0,   // waiting for top2imm_valid
        S_KICK_LUT    = 3'd1,   // assert ctrl2psum_addr_valid; wait for handshake
        S_WAIT_LUT    = 3'd2,   // wait for psum2ctrl_addr_ready HIGH (pair done)
        S_NEXT_PAIR   = 3'd3,   // advance (s,n) counters; compute next LUT address
        S_WAIT_SPAD   = 3'd4,   // wait for Scratchpad accumulation done
        S_GIVE_SPAD   = 3'd5,   // deliver output base address to Scratchpad
        S_WAIT_STREAM = 3'd6,   // wait for Scratchpad streaming done
        S_DONE        = 3'd7;   // pulse imm_done, back to IDLE

    reg [2:0] cs, ns;

    // =========================================================
    //  Loop counters
    // =========================================================
    reg [K_CNT_WIDTH-1:0] subspace_count;   // inner: 0 .. k_total-1
    reg [N_CNT_WIDTH-1:0] n_count;          // outer: 0 .. n_total-1

    // =========================================================
    //  State register
    // =========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cs <= S_IDLE;
        else        cs <= ns;
    end

    // =========================================================
    //  Next-state logic
    // =========================================================
    always @(*) begin
        ns = cs;
        case (cs)

            S_IDLE:
                if (top2imm_valid && imm2top_ready)
                    ns = S_KICK_LUT;

            // Handshake: psum2ctrl_addr_ready HIGH = PSumLUT accepts the address.
            // After acceptance PSumLUT drives psum2ctrl_addr_ready LOW (registered),
            // so the transition fires on the same cycle as the handshake.
            S_KICK_LUT:
                if (ctrl2psum_addr_valid && psum2ctrl_addr_ready)
                    ns = S_WAIT_LUT;

            // psum2ctrl_addr_ready goes LOW (address taken) then back HIGH (M entries done).
            // At entry to S_WAIT_LUT it is already LOW, so HIGH = pair done.
            S_WAIT_LUT:
                if (psum2ctrl_addr_ready)
                    ns = S_NEXT_PAIR;

            // Advance counters; next-state decision based on CURRENT counter values
            // (before the increment that happens in the datapath this cycle).
            S_NEXT_PAIR:
                if (subspace_count == k_total - 1 && n_count == n_total - 1)
                    ns = S_WAIT_SPAD;
                else
                    ns = S_KICK_LUT;

            S_WAIT_SPAD:
                if (spad2ctrl_addr_ready)
                    ns = S_GIVE_SPAD;

            // Scratchpad de-asserts spad2ctrl_addr_ready once it latches the address.
            S_GIVE_SPAD:
                if (!spad2ctrl_addr_ready)
                    ns = S_WAIT_STREAM;

            S_WAIT_STREAM:
                if (spad2ctrl_done)
                    ns = S_DONE;

            S_DONE:
                ns = S_IDLE;

            default: ns = S_IDLE;
        endcase
    end

    // =========================================================
    //  Output / Datapath Logic
    // =========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            imm2top_ready        <= 1'b1;
            imm_done             <= 1'b0;
            ctrl2psum_addr_valid <= 1'b0;
            ctrl2psum_start_addr <= {MEM_ADDR_WIDTH{1'b0}};
            ctrl2spad_addr_valid <= 1'b0;
            ctrl2spad_start_addr <= {MEM_ADDR_WIDTH{1'b0}};
            subspace_count       <= {K_CNT_WIDTH{1'b0}};
            n_count              <= {N_CNT_WIDTH{1'b0}};
        end else begin
            imm_done <= 1'b0;

            case (cs)

                // ── IDLE ──────────────────────────────────────────────
                S_IDLE: begin
                    imm2top_ready        <= 1'b1;
                    ctrl2psum_addr_valid <= 1'b0;
                    ctrl2spad_addr_valid <= 1'b0;
                    subspace_count       <= {K_CNT_WIDTH{1'b0}};
                    n_count              <= {N_CNT_WIDTH{1'b0}};

                    if (top2imm_valid && imm2top_ready) begin
                        imm2top_ready        <= 1'b0;
                        ctrl2psum_start_addr <= {MEM_ADDR_WIDTH{1'b0}}; // s=0, n=0 → addr=0
                        // Latch the output base address at run start so it is
                        // stable for the entire run. Prevents a stale value from
                        // a previous run being captured by the Scratchpad's
                        // GET_ADDR handshake before S_GIVE_SPAD settles.
                        ctrl2spad_start_addr <= spad_out_addr;
                    end
                end

                // ── KICK PSumLUT ───────────────────────────────────────
                S_KICK_LUT: begin
                    ctrl2psum_addr_valid <= 1'b1;
                    if (ctrl2psum_addr_valid && psum2ctrl_addr_ready)
                        ctrl2psum_addr_valid <= 1'b0;
                end

                // ── WAIT FOR PAIR DONE ─────────────────────────────────
                S_WAIT_LUT: begin
                    ctrl2psum_addr_valid <= 1'b0;
                    // psum2ctrl_addr_ready LOW → HIGH triggers S_NEXT_PAIR
                end

                // ── ADVANCE COUNTERS & PRE-COMPUTE NEXT LUT ADDRESS ────
                // Runs exactly 1 cycle; new ctrl2psum_start_addr is stable
                // by the time S_KICK_LUT starts the next handshake.
                S_NEXT_PAIR: begin
                    if (subspace_count == k_total - 1) begin
                        // ---- End of column: wrap subspace to 0 ----
                        subspace_count <= {K_CNT_WIDTH{1'b0}};

                        if (n_count < n_total - 1) begin
                            n_count <= n_count + 1'b1;

                            // addr(s=0, n+1) = 0*(N*C) + (n+1)*C
                            ctrl2psum_start_addr <= (n_count + 1) * NUM_CENTROIDS;
                        end
                        // else: last pair → going to S_WAIT_SPAD, no addr update needed
                    end else begin
                        // ---- Next subspace in same column ----
                        subspace_count <= subspace_count + 1'b1;

                        // addr(s+1, n) = (s+1)*N*C + n*C
                        ctrl2psum_start_addr <= (subspace_count + 1) * (N * NUM_CENTROIDS)
                                               + n_count * NUM_CENTROIDS;
                    end
                end

                // ── WAIT FOR SCRATCHPAD ACCUMULATION ──────────────────
                S_WAIT_SPAD: ;  // spad2ctrl_addr_ready rise handled in next-state

                // ── DELIVER OUTPUT BASE ADDRESS ────────────────────────
                S_GIVE_SPAD: begin
                    ctrl2spad_start_addr <= spad_out_addr;
                    ctrl2spad_addr_valid <= 1'b1;
                    if (!spad2ctrl_addr_ready)
                        ctrl2spad_addr_valid <= 1'b0;
                end

                // ── WAIT FOR STREAMING ─────────────────────────────────
                S_WAIT_STREAM: begin
                    ctrl2spad_addr_valid <= 1'b0;
                end

                // ── DONE ───────────────────────────────────────────────
                S_DONE: begin
                    imm_done      <= 1'b1;
                    imm2top_ready <= 1'b1;
                end

                default: begin
                    imm2top_ready        <= 1'b1;
                    imm_done             <= 1'b0;
                    ctrl2psum_addr_valid <= 1'b0;
                    ctrl2spad_addr_valid <= 1'b0;
                end
            endcase
        end
    end

endmodule
