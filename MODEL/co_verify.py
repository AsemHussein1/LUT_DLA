"""
co_verify.py  —  RTL co-verification golden model
===================================================
Generates deterministic test vectors that match the RTL DLA parameters
exactly, runs the Python reference computation, and writes four hex
init files for the SystemVerilog testbench (TC21).

RTL parameters (must match SYSTEM_TOP_TB.sv localparam):
    K   = 16   subspaces
    C   = 16   centroids per subspace  (NUM_CENTROIDS)
    M   = 20   input rows
    N   = 16   output columns
    L   = 2    subvector length        (VECTOR_LENGTH)

Algorithm (mirrors RTL exactly):
    For each input row m (0..M-1):
        For each subspace k (0..K-1):
            subvec  = ISRAM[k*M + m]   (2 bytes)
            c_star  = argmin_c L1(subvec, CSRAM[k*C + c])   (integer L1)
            For each output col n (0..N-1):
                output[m][n] += LSRAM[k*(N*C) + n*C + c_star]

Output files (written to the MODEL/ directory):
    csram_init.hex       K*C    lines, 4-hex-digit each (16-bit)
    isram_init.hex       K*M    lines, 4-hex-digit each (16-bit)
    lsram_init.hex       K*N*C  lines, 2-hex-digit each  (8-bit)
    expected_osram.hex   M*N    lines, 8-hex-digit each (32-bit)

Usage:
    python MODEL/co_verify.py

Then launch ModelSim:
    vsim -do run_sim.do
TC21 reads the files, loads the SRAMs, runs the RTL, and compares.
"""

import numpy as np
import os
import sys

# ── RTL parameters (keep in sync with SYSTEM_TOP_TB.sv) ──────────────
K = 16   # subspaces
C = 16   # centroids per subspace  (NUM_CENTROIDS)
M = 20   # input rows
N = 16   # output columns
L = 2    # subvector length (VECTOR_LENGTH)

SEED = 42  # fixed seed -> reproducible across Python and TB runs

print("=" * 60)
print("LUT-DLA Co-Verification Golden Model")
print(f"  K={K} subspaces, C={C} centroids, M={M} inputs, N={N} outputs, L={L}")
print("=" * 60)

# ── Generate deterministic test data ─────────────────────────────────
rng = np.random.default_rng(SEED)

# centroids[k, c, :] = L-byte centroid vector for subspace k, centroid c
centroids = rng.integers(0, 256, size=(K, C, L), dtype=np.uint8)

# inputs[m, k, :] = L-byte subvector for input row m, subspace k
inputs = rng.integers(0, 256, size=(M, K, L), dtype=np.uint8)

# lut[k, c, n] = 8-bit LUT entry: subspace k, centroid c, output col n
lut = rng.integers(0, 256, size=(K, C, N), dtype=np.uint8)

# ── Python golden: L1 nearest centroid + accumulate ──────────────────
output = np.zeros((M, N), dtype=np.int64)

nearest = np.zeros((M, K), dtype=np.int32)   # for diagnostic display

for m in range(M):
    for k in range(K):
        subvec = inputs[m, k].astype(np.int32)
        # L1 distance to every centroid in this subspace
        l1 = np.sum(np.abs(centroids[k].astype(np.int32) - subvec), axis=1)
        c_star = int(np.argmin(l1))   # lowest index wins ties (matches RTL)
        nearest[m, k] = c_star
        output[m] += lut[k, c_star].astype(np.int64)

print(f"\nGolden computation complete.")
print(f"  Max output value : {output.max()}  (RTL max: {K * 255} = {K*255})")
print(f"  Min output value : {output.min()}")
print(f"\nFirst 3 output rows:")
for m in range(min(3, M)):
    print(f"  output[{m}] = {output[m].tolist()}")

print(f"\nExpected c_star for subspace k=0 (rows m=0..{M-1}) — compare with [CSTAR] #0..{M-1}:")
print(f"  nearest[:,0] = {nearest[:,0].tolist()}")
print(f"Expected c_star for subspace k=1 (rows m=0..3) — compare with [CSTAR] #{M}..{M+3}:")
print(f"  nearest[0:4,1] = {nearest[0:4,1].tolist()}")

# ── Write init files ──────────────────────────────────────────────────
out_dir = os.path.dirname(os.path.abspath(__file__))

# --- CSRAM: K*C entries, address = k*C + c, value = 16-bit {comp1, comp0} ---
csram_path = os.path.join(out_dir, "csram_init.hex")
with open(csram_path, "w") as f:
    for k in range(K):
        for c in range(C):
            val = (int(centroids[k, c, 1]) << 8) | int(centroids[k, c, 0])
            f.write(f"{val:04x}\n")
print(f"\nWrote {K*C} entries -> {csram_path}")

# --- ISRAM: K*M entries, address = k*M + m, value = 16-bit {comp1, comp0} ---
isram_path = os.path.join(out_dir, "isram_init.hex")
with open(isram_path, "w") as f:
    for k in range(K):
        for m in range(M):
            val = (int(inputs[m, k, 1]) << 8) | int(inputs[m, k, 0])
            f.write(f"{val:04x}\n")
print(f"Wrote {K*M} entries -> {isram_path}")

# --- LSRAM: K*N*C entries, address = k*(N*C) + n*C + c, value = 8-bit ---
lsram_path = os.path.join(out_dir, "lsram_init.hex")
with open(lsram_path, "w") as f:
    for k in range(K):
        for n in range(N):
            for c in range(C):
                f.write(f"{int(lut[k, c, n]):02x}\n")
print(f"Wrote {K*N*C} entries -> {lsram_path}")

# --- Expected OSRAM: M*N entries, address = m*N + n, value = 32-bit ---
osram_path = os.path.join(out_dir, "expected_osram.hex")
with open(osram_path, "w") as f:
    for m in range(M):
        for n in range(N):
            f.write(f"{int(output[m, n]):08x}\n")
print(f"Wrote {M*N} entries -> {osram_path}")

# --- Human-readable final output matrix (M x N) ----------------------
# Mirrors the RTL matrix the testbench prints / writes to
# MODEL/rtl_osram_matrix.txt, so the two can be diffed directly.
matrix_path = os.path.join(out_dir, "output_matrix.txt")
with open(matrix_path, "w") as f:
    for m in range(M):
        f.write(" ".join(str(int(output[m, n])) for n in range(N)) + "\n")
print(f"Wrote {M}x{N} output matrix -> {matrix_path}")

print("\nFinal output matrix (Python golden, M rows x N cols):")
for m in range(M):
    print("  row{:2d}: ".format(m) + " ".join("{:4d}".format(int(output[m, n])) for n in range(N)))

print("\nAll files ready. Run ModelSim -> TC21 will verify the RTL.")
