# NVDLA_LUT_BASED — Technical Reference

## Project Overview

NVDLA_LUT_BASED is a hardware accelerator implementing LUT-based approximate matrix multiplication via Product Quantization (PQ), comprising a CCM pipeline for centroid index generation and an IMM pipeline for partial-sum lookup and accumulation. The system decouples the two pipelines across separate clock domains using an asynchronous FIFO, supporting the LUT-Stationary (LS) dataflow.

---

## Global Parameters

| Parameter | Description |
|-----------|-------------|
| `V` | Sub-vector length |
| `C` | Centroids per subspace (codebook size); index width = log2(C) |
| `Tn` | Tile length in the N dimension |
| `Nc` | Number of subspaces/codebooks; Nc = K/V |
| `L` | Number of CCUs inside one CCM |
| `M, K` | Input matrix dimensions (A[M×K]) |
| `K, N` | Weight matrix dimensions (B[K×N]) |

---

## Block Reference

---

### CCM — Centroid Computation Module

**Purpose:** Implements the similarity-comparison step; outputs the nearest centroid index for each input sub-vector.

**Sub-blocks:** Centroid Buffer, Input Buffer, CCU(s)

**Parallelism:** Multiple CCUs share one Centroid Buffer and one Input Buffer within a CCM. CCM runs at the higher clock domain.

---

#### Centroid Buffer

**Purpose:** High-speed local cache for the active subspace's centroid vectors; dual-mode (serial load from memory, parallel output to CCU).

**Parameters:**

| Parameter | Description | Value |
|-----------|-------------|-------|
| `NUM_CENTROIDS` | Centroids per subspace (C) | — |
| `VECTOR_LENGTH` | Elements per centroid vector | — |
| `CENTROID_WIDTH` | Bit-width per centroid element | — |
| `ADDR_WIDTH` | Internal counter width | log2(NUM_CENTROIDS) |
| `MEM_ADDR_WIDTH` | External memory address width | — |

**Ports:**

| Name | Dir | Width | Description |
|------|-----|-------|-------------|
| `clk` | In | 1 | CCM high-speed clock |
| `rst_n` | In | 1 | Async active-low reset |
| `addr_ready` | Out | 1 | Buffer idle; ready to accept new `start_addr` |
| `start_addr` | In | MEM_ADDR_WIDTH | Base address of first centroid in current subspace |
| `addr_valid` | In | 1 | `start_addr` is valid (from controller) |
| `cb2mem_addr` | Out | MEM_ADDR_WIDTH | Address of centroid to fetch from memory |
| `cb2mem_valid` | Out | 1 | `cb2mem_addr` is valid |
| `mem2cb_centroid` | In | CENTROID_WIDTH×VECTOR_LENGTH | Serial centroid vector returned from memory |
| `mem2cb_valid` | In | 1 | `mem2cb_centroid` is valid |
| `ccu2cb_ready` | In | 1 | CCU ready to receive parallel centroid data |
| `cb2ccu_centroid` | Out | NUM_CENTROIDS×CENTROID_WIDTH×VECTOR_LENGTH | All centroids for active subspace (parallel) |
| `cb2ccu_valid` | Out | 1 | All centroids loaded and ready for CCU |

**FSM States:**

| State | Description |
|-------|-------------|
| `IDLE` | Waiting for `addr_valid`; asserts `addr_ready` |
| `LOADING` | Sequentially fetching centroids from memory via `cb2mem_addr/valid`; writes on `mem2cb_valid` |
| `READY` | All centroids loaded; drives `cb2ccu_centroid` parallel bus; asserts `cb2ccu_valid` |

**Internal Signals:**

| Signal | Description |
|--------|-------------|
| `addr_counter` | Increments 0→NUM_CENTROIDS during LOADING |
| `mem_bank[0..C-1]` | Register array storing fetched centroid vectors |

---

#### Input Buffer

**Purpose:** Stores all vectors for one subspace of the input matrix A; decouples memory latency from CCU compute.

**Parameters:**

| Parameter | Description | Value |
|-----------|-------------|-------|
| `VECTOR_WIDTH` | Bit-width of one sub-vector (V × element width) | — |

**Ports:**

| Name | Dir | Width | Description |
|------|-----|-------|-------------|
| `clk` | In | 1 | CCM high-speed clock |
| `rst_n` | In | 1 | Async active-low reset |
| `ctrl2ipbuff_ready` | Out | 1 | Buffer ready to accept new `initial_idx` |
| `ctrl2ipbuff_valid` | In | 1 | `initial_idx` is valid (controller → buffer) |
| `initial_idx` | In | MEM_ADDR_WIDTH | Base address of first sub-vector in subspace |
| `Ipbuff2dbb_arvalid` | Out | 1 | Memory read address valid |
| `Ipbuff2dbb_araddr` | Out | MEM_ADDR_WIDTH | Memory read address |
| `Ipbuff2dbb_rdata` | In | VECTOR_WIDTH | Sub-vector fetched from memory |
| `ctrl2ipbuff_rready` | In | 1 | CCU ready to accept next vector |
| `Ipbuff2ccu_valid` | Out | 1 | Output vector to CCU is valid |
| `Output_vector` | Out | VECTOR_WIDTH | Sub-vector output to CCU |

**FSM States:**

| State | Description |
|-------|-------------|
| `IDLE` | Waiting for `ctrl2ipbuff_valid`; asserts `ctrl2ipbuff_ready` |
| `LOADING` | Counter 0→M; fetches sub-vectors from memory; deasserts `ctrl2ipbuff_ready` |
| `UPLOADING` | Counter M→0; drives `Output_vector`; asserts `Ipbuff2ccu_valid` |

**Internal Signals:**

| Signal | Description |
|--------|-------------|
| `row_counter` | Counts 0→M (load) then M→0 (upload) |
| `vector_bank[0..M-1]` | Stores fetched sub-vectors |

---

#### CCU — Centroid Computation Unit

**Purpose:** Pipelined chain of dPEs; computes distance between each input sub-vector and all C centroids; outputs nearest centroid index.

**Parameters:**

| Parameter | Description |
|-----------|-------------|
| `C` | Number of centroids = number of dPEs |
| `V` | Sub-vector dimension |
| `INITIAL_MIN_DIST` | Initial minimum distance (must be max value) |
| `INITIAL_INDEX` | Seed index for first dPE |
| Similarity Metric | L1 / L2 / Chebyshev (runtime-selectable) |

**Ports:**

| Name | Dir | Width | Description |
|------|-----|-------|-------------|
| `clk` | In | 1 | CCM clock |
| `rst_n` | In | 1 | Async active-low reset |
| `I_P_subvector` | In | VECTOR_WIDTH | Input sub-vector from Input Buffer |
| `Centroids` | In | C×VECTOR_WIDTH | Parallel centroids from Centroid Buffer |
| `Controller2CCU_valid` | In | 1 | Both IB and CB hold valid data; start processing |
| `M` | In | — | Number of input matrix rows |
| `Similarity_Metric` | In | 2 | Selects L1 / L2 / Chebyshev |
| `CCU_ready2IB` | Out | 1 | CCU ready to accept next sub-vector |
| `CCU_ready2CB` | Out | 1 | CCU ready to accept centroid data |
| `Index_valid` | Out | 1 | `Min_Index` output is valid |
| `Min_Index` | Out | log2(C) | Index of nearest centroid |
| `Min_Distance` | Out | — | Minimum distance (optional, for metrics) |
| `CCU_done` | Out | 1 | All sub-vectors in subspace processed |

**Internal Signals:**

| Signal | Description |
|--------|-------------|
| `dPE_chain[0..C-1]` | Pipeline of distance Processing Elements |
| `running_min_dist` | Propagated minimum distance through dPE chain |
| `running_min_idx` | Propagated minimum index through dPE chain |
| `vector_counter` | Counts processed vectors; compared against M |

**dPE Operation:** Each dPE holds one centroid. On each cycle it computes `dist(input, centroid_i)`, compares with incoming `running_min_dist`, propagates the smaller value and corresponding index downstream.

---

### FIFO — Asynchronous Indices Buffer

**Purpose:** Clock-domain crossing FIFO decoupling CCM (write, high-freq) from IMM (read, low-freq); caches centroid indices.

**Ports:**

| Name | Dir | Width | Description |
|------|-----|-------|-------------|
| `wr_clk` | In | 1 | CCM clock (high frequency) |
| `rd_clk` | In | 1 | IMM clock (low frequency) |
| `rst_n` | In | 1 | Async reset |
| `wr_en` | In | 1 | Write enable |
| `rd_en` | In | 1 | Read enable |
| `din` | In | log2(C) | Centroid index from CCU |
| `dout` | Out | log2(C) | Centroid index to IMM/PSum |
| `is_full` | Out | 1 | FIFO full flag |
| `is_empty` | Out | 1 | FIFO empty flag |

---

### IMM — In-Memory Matching Module

**Purpose:** Implements LUT loading and table lookup; uses centroid indices to fetch precomputed partial sums and accumulates the output matrix.

**Sub-blocks:** PSum LUT (Ping-Pong Buffer), Scratchpad

---

#### PSum LUT (Ping-Pong Buffer)

**Purpose:** Double-buffered storage for precomputed partial sums (centroids × weight columns); replaces multiply-accumulate with table lookup; hides memory load latency via ping-pong banking.

**Ports:**

| Name | Dir | Width | Description |
|------|-----|-------|-------------|
| `clk` | In | 1 | IMM low-speed clock |
| `rst_n` | In | 1 | Async active-low reset |
| `Psum2FIFO_valid` | Out | 1 | Data request to FIFO |
| `Psum2FIFO_ready` | In | 1 | FIFO handshake return |
| `Fifo2PSum_valid` | In | 1 | Index from FIFO is valid |
| `Fifo2PSum_index` | In | log2(C) | Centroid index from FIFO |
| `Psum2SP_valid` | Out | 1 | Data packet to Scratchpad is valid |
| `SP2Psum_ready` | In | 1 | Scratchpad ready handshake |
| `Psum2SP_packet` | Out | — | Looked-up PSum value + current N |
| `Control2PSum_valid` | In | 1 | New LUT load request from controller |
| `Control2PSum_ready` | Out | 1 | PSum ready for load request |
| `Control2PSum_ss_address` | In | ss_addr_width+log2(N) | New subspace LUT base address + N index |
| `PSum2Control_Status0` | Out | 1 | Bank 0 idle/in-use status |
| `PSum2Control_Status1` | Out | 1 | Bank 1 idle/in-use status |
| `Producer` | In | 1 | Controller selects shadow bank for loading |
| `Consumer` | In | 1 | Controller selects active bank for lookup |
| `Enable0` | In | 1 | Enable read from Bank 0 |
| `Enable1` | In | 1 | Enable read from Bank 1 |
| `PSum2DMA_valid` | Out | 1 | DMA load request valid |
| `DMA2PSUM_ready` | In | 1 | DMA ready handshake |
| `PSum2DMA_address` | Out | — | DMA load address |
| `DMA2PSUM_valid` | In | 1 | DMA response valid |
| `PSum2DMA_ready` | In | 1 | PSum ready for DMA response |
| `DMA2PSUM_data` | In | — | LUT data from DMA |

**Internal Signals:**

| Signal | Description |
|--------|-------------|
| `Bank0[0..C-1]`, `Bank1[0..C-1]` | Two LUT banks (ping-pong) |
| `active_bank` | Points to Consumer bank (lookup) |
| `shadow_bank` | Points to Producer bank (loading) |
| `Status0`, `Status1` | Idle / In-use state per bank (mirrored to controller) |

**Bank Swap Protocol (per K-loop boundary):**
1. Controller sets idle bank's `Status` → clears its `Enable` → sets `Consumer` to new bank.
2. Computation continues on new active bank (waits if `Enable` not yet set).
3. Controller sets `Producer` to shadow bank → sends `Control2PSum_valid` + new address.
4. DMA loads shadow bank → PSum asserts `Enable` when done.

---

#### Scratchpad

**Purpose:** Accumulates partial sums from PSum LUT per output matrix element; outputs completed row accumulations for post-processing.

**Ports:**

| Name | Dir | Width | Description |
|------|-----|-------|-------------|
| `clk` | In | 1 | IMM clock |
| `rst_n` | In | 1 | Async active-low reset |
| `pSum_lut_in` | In | 16/32 | Partial sum value from PSum LUT |
| `row_idx_in` | In | log2(M) | Current input matrix row index (M dimension) |
| `In_valid` | In | 1 | `pSum_lut_in` and `row_idx_in` are valid |
| `Wt_in` | In | log2(N) | Current weight column index (N dimension) |
| `In_ready` | Out | 1 | Scratchpad ready to accept data |
| `data_out` | Out | 16/32 | Final accumulated value for output element |
| `out_valid` | Out | 1 | `data_out` contains a completed accumulation |

**Internal Signals:**

| Signal | Description |
|--------|-------------|
| `acc_array[M][N]` | Accumulator register bank |
| `subspace_counter` | Counts Nc subspaces; `out_valid` asserted at Nc |

---

## Block Interconnections

```
External Memory
      │  (centroids)           │  (input vectors)        │  (PSum LUT data via DMA)
      ▼                        ▼                          ▼
Centroid Buffer          Input Buffer               PSum LUT (Bank0/Bank1)
      │ cb2ccu_centroid        │ Output_vector             │ Psum2SP_packet
      └──────────┬─────────────┘                          │
                 ▼                                        │
                CCU                                       │
                 │ Min_Index / Index_valid                │
                 ▼                                        │
        Async FIFO (Indices Buffer)                       │
          wr_clk=CCM_clk  rd_clk=IMM_clk                 │
                 │ dout / Fifo2PSum_index                 │
                 └──────────────►  PSum LUT ◄─────────────┘
                                      │ Psum2SP_packet
                                      ▼
                                 Scratchpad
                                      │ data_out / out_valid
                                      ▼
                             Dequant & Activation (downstream)
```

**Controller wires to:**

| Controller Signal | Target |
|-------------------|--------|
| `start_addr` / `addr_valid` | Centroid Buffer |
| `initial_idx` / `ctrl2ipbuff_valid` | Input Buffer |
| `Controller2CCU_valid` | CCU |
| `Consumer`, `Producer`, `Enable0/1`, `Control2PSum_valid/ss_address` | PSum LUT |

---

## Timing & Protocol Notes

| Aspect | Detail |
|--------|--------|
| Clock domains | CCM: high-frequency; IMM: low-frequency |
| CDC mechanism | Asynchronous FIFO between CCU output and PSum LUT input |
| Handshake protocol | Valid/Ready throughout (consistent with NVDLA conventions) |
| Centroid Buffer load | Sequential memory reads; write locked during compute phase |
| Input Buffer phases | Load (0→M, memory read) then Upload (M→0, drive CCU) — sequential, non-overlapping |
| PSum ping-pong | Shadow bank loads concurrently while active bank serves lookups; swap gated by `Enable` flag |
| CCU pipeline depth | C stages (one dPE per centroid); full pipeline occupancy after C cycles |
| LUT-Stationary dataflow | Entire M dimension processed per subspace before K advances; minimises centroid buffer reloads |
| Scratchpad `out_valid` | Asserted by internal subspace counter reaching Nc (all partial sums accumulated) |
