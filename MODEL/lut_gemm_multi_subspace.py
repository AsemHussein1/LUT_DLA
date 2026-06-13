import numpy as np
from sklearn.cluster import KMeans
import os

TRAINING_VECTORS_FILE = r"C:\Users\tarek\Downloads\training_data.txt"
NUMBER_OF_CENTROIDS = 300
NUMBER_OF_SUBSPACES = 3   # <-- NEW: how many subspaces to split each row into
SIMILARITY = "L2"         # 'L2', 'L1', 'Chebyshev'


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def split_into_subvectors(matrix, num_subspaces):
    """
    Split every row of `matrix` into `num_subspaces` equal-length subvectors.

    Returns a list of sub-matrices, one per subspace.
    Shape of each sub-matrix: (num_rows, subvector_length)

    Raises ValueError if the number of columns is not evenly divisible.
    """
    num_cols = matrix.shape[1]
    if num_cols % num_subspaces != 0:
        raise ValueError(
            f"Vector length {num_cols} is not evenly divisible "
            f"by num_subspaces={num_subspaces}."
        )
    subvector_len = num_cols // num_subspaces
    return [matrix[:, s * subvector_len:(s + 1) * subvector_len]
            for s in range(num_subspaces)]


def calculate_centroids(training_subvectors, num_of_centroids):
    """Run KMeans on a sub-matrix and return cluster centres."""
    kmeans = KMeans(n_clusters=num_of_centroids, n_init=1000)
    kmeans.fit(training_subvectors)
    return kmeans.cluster_centers_


def precompute_lut(centroids, weight_submatrix):
    """
    LUT[k] = centroids[k] @ weight_submatrix
    Shape: (num_centroids, num_weight_cols)
    """
    return np.dot(centroids, weight_submatrix)


def find_nearest_centroid(subvector, centroids, similarity='L2'):
    """Return the index of the closest centroid to `subvector`."""
    if similarity == 'L2':
        diffs = centroids - subvector          # (K, d)
        distances = np.linalg.norm(diffs, axis=1)
    elif similarity == 'L1':
        distances = np.sum(np.abs(centroids - subvector), axis=1)
    elif similarity == 'Chebyshev':
        distances = np.max(np.abs(centroids - subvector), axis=1)
    else:
        raise ValueError(f"Unknown similarity metric: {similarity}")
    return np.argmin(distances)


# ---------------------------------------------------------------------------
# Core: multi-subspace LUT matmul
# ---------------------------------------------------------------------------

def train_subspace_codebooks(training_submatrices, num_of_centroids):
    """
    For each subspace, compute KMeans centroids.

    Returns:
        all_centroids  – list of (num_centroids, subvector_len) arrays
    """
    all_centroids = []
    for s, sub in enumerate(training_submatrices):
        print(f"  [Subspace {s}] fitting KMeans on shape {sub.shape} ...")
        centroids = calculate_centroids(sub, num_of_centroids)
        all_centroids.append(centroids)
        print(f"  [Subspace {s}] centroids:\n{centroids}")
    return all_centroids


def build_all_luts(all_centroids, weight_submatrices):
    """
    For each subspace s, build LUT_s = centroids_s @ weight_submatrix_s.

    weight_submatrices[s] has shape (subvector_len, num_weight_cols).
    LUT_s has shape (num_centroids, num_weight_cols).

    Returns:
        all_luts – list of (num_centroids, num_weight_cols) arrays
    """
    all_luts = []
    for s, (centroids, W_sub) in enumerate(zip(all_centroids, weight_submatrices)):
        lut = precompute_lut(centroids, W_sub)
        all_luts.append(lut)
        print(f"  [Subspace {s}] LUT shape {lut.shape}:\n{lut}")
    return all_luts


def lut_matmul_multi_subspace(input_submatrices, all_centroids, all_luts, similarity):
    """
    Approximate matrix multiplication via multi-subspace LUT lookup.

    For each row r:
        output[r] = sum over subspaces s of:
                        LUT_s[ nearest_centroid(input_submatrices[s][r]) ]

    Returns:
        result – (num_rows, num_weight_cols)
    """
    num_rows      = input_submatrices[0].shape[0]
    num_weight_cols = all_luts[0].shape[1]
    num_subspaces   = len(all_luts)

    result = np.zeros((num_rows, num_weight_cols))

    for r in range(num_rows):
        for s in range(num_subspaces):
            subvec  = input_submatrices[s][r, :]
            c_idx   = find_nearest_centroid(subvec, all_centroids[s], similarity)
            result[r, :] += all_luts[s][c_idx]

    return result


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

# --- Load training vectors --------------------------------------------------
print("=" * 60)
print("Loading training vectors")
if os.path.exists(TRAINING_VECTORS_FILE):
    training_vectors = np.loadtxt(TRAINING_VECTORS_FILE)
    print("training_vectors shape:", training_vectors.shape)
    print(training_vectors)
else:
    print("ERROR: training vectors file is not found")
    exit()

vector_length = training_vectors.shape[1]

# --- Input matrix -----------------------------------------------------------
input_matrix = np.array([
    [142,   37,  219, 84, 11,  173],
    [255,   96,  58, 201, 134,  7],
    [96, 188,  243,  120, 45, 154]
])

print("\nInput matrix:")
print(input_matrix)

# Validate dimensions
if input_matrix.shape[1] != vector_length:
    print("ERROR: input matrix column count must match training vector length")
    exit()

if vector_length % NUMBER_OF_SUBSPACES != 0:
    print(f"ERROR: vector length {vector_length} not divisible "
          f"by NUMBER_OF_SUBSPACES={NUMBER_OF_SUBSPACES}")
    exit()

subvector_len = vector_length // NUMBER_OF_SUBSPACES
print(f"\nSubspace config: {NUMBER_OF_SUBSPACES} subspaces, "
      f"subvector length = {subvector_len}")

# --- Weight matrix ----------------------------------------------------------
# Must have `vector_length` rows (one weight row per input feature).
# Here: 6 input features, 3 output features.
weight_matrix = np.array([
    [183, 24, 217],
    [91, 255, 48],
    [132, 76, 201],
    [5, 149, 88],
    [224, 37, 170],
    [118, 203, 12]
])

# Split the weight matrix row-wise: subspace s uses rows [s*sub_len : (s+1)*sub_len]
weight_submatrices = [
    weight_matrix[s * subvector_len:(s + 1) * subvector_len, :]
    for s in range(NUMBER_OF_SUBSPACES)
]

# --- Split training vectors and input matrix into subspaces -----------------
training_submatrices = split_into_subvectors(training_vectors, NUMBER_OF_SUBSPACES)
input_submatrices    = split_into_subvectors(input_matrix,     NUMBER_OF_SUBSPACES)

# --- Training Phase ---------------------------------------------------------
print("\n" + "=" * 60)
print("Training Phase – computing per-subspace centroids")
all_centroids = train_subspace_codebooks(training_submatrices, NUMBER_OF_CENTROIDS)

# --- Precomputation Phase ---------------------------------------------------
print("\n" + "=" * 60)
print("Precomputation Phase – building per-subspace LUTs")
all_luts = build_all_luts(all_centroids, weight_submatrices)

# --- Inference Phase --------------------------------------------------------
print("\n" + "=" * 60)
print("Inference Phase – multi-subspace LUT matmul")
output_matrix = lut_matmul_multi_subspace(
    input_submatrices, all_centroids, all_luts, SIMILARITY
)
print("\nOutput Matrix (LUT approximation):")
print(output_matrix)

# --- Ground-truth comparison ------------------------------------------------
exact_output = input_matrix @ weight_matrix
print("\nExact Matrix Multiplication (ground truth):")
print(exact_output)

print("\nApproximation Error (abs):")
print(np.abs(output_matrix - exact_output))
print(f"Max error: {np.max(np.abs(output_matrix - exact_output)):.4f}")
print(f"Mean error: {np.mean(np.abs(output_matrix - exact_output)):.4f}")
