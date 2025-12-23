# ============================================================
#   NYCU IC Lab06 - Huffman Code (Python Golden Reference)
#   - Follows Lab06 tie-break & merge rules
#   - Generates Huffman codebook for 8 chars: A B C E I L O V
#   - Encodes ILOVE & ICLAB
#   - Optional: export CSV test vectors
# ============================================================

import csv

# ------------------------------------------------------------
# Node class for building the Huffman tree
# ------------------------------------------------------------
class Node:
    def __init__(self, weight, is_leaf, symbol=None, left=None, right=None, create_idx=0):
        self.weight = weight
        self.is_leaf = is_leaf
        self.symbol = symbol      # A .. V for leaves
        self.left = left          # left child (weight larger)
        self.right = right        # right child (weight smaller)
        self.create_idx = create_idx  # older subtree has smaller create_idx

    def __repr__(self):
        if self.is_leaf:
            return f"Leaf({self.symbol},{self.weight})"
        return f"Node(w={self.weight},idx={self.create_idx})"


# ------------------------------------------------------------
# Characters defined in the Lab spec (fixed order)
# ------------------------------------------------------------
CHARS = ['A','B','C','E','I','L','O','V']


# ------------------------------------------------------------
# Sorting key according to Lab06 rules:
# 1. Weight ascending
# 2. Leaf before subtree
# 3. If both leaves: by character order A>B>C>E>I>L>O>V
# 4. If both subtree: older subtree (smaller create_idx) first
# ------------------------------------------------------------
def sort_key(node):
    w = node.weight
    t = 0 if node.is_leaf else 1  # leaf first
    if node.is_leaf:
        char_rank = CHARS.index(node.symbol)
        return (w, t, char_rank, node.create_idx)
    else:
        return (w, t, node.create_idx, 0)


# ------------------------------------------------------------
# Build Huffman tree from 8 weights
# ------------------------------------------------------------
def build_huffman_from_weights(weights):
    nodes = []
    create_counter = 0

    # Build leaf nodes
    for sym, w in zip(CHARS, weights):
        nodes.append(Node(weight=w, is_leaf=True, symbol=sym, create_idx=create_counter))
        create_counter += 1

    if len(nodes) == 1:
        return {nodes[0].symbol: "0"}, nodes[0]

    # Iteratively combine
    while len(nodes) > 1:
        nodes.sort(key=sort_key)
        n1 = nodes.pop(0)
        n2 = nodes.pop(0)

        # Determine left/right: left = larger node, right = smaller node
        k1 = sort_key(n1)
        k2 = sort_key(n2)

        if k1 < k2:
            left, right = n2, n1
        else:
            left, right = n1, n2

        merged = Node(weight=n1.weight + n2.weight,
                      is_leaf=False,
                      left=left,
                      right=right,
                      create_idx=create_counter)
        create_counter += 1
        nodes.append(merged)

    root = nodes[0]

    # DFS generate codes
    codes = {}
    def dfs(n, prefix):
        if n.is_leaf:
            codes[n.symbol] = prefix or "0"
            return
        dfs(n.left,  prefix + "0")
        dfs(n.right, prefix + "1")

    dfs(root, "")
    return codes, root


# ------------------------------------------------------------
# Encode a string with codebook
# ------------------------------------------------------------
def encode_string(s, codes):
    return "".join(codes[ch] for ch in s)


# ------------------------------------------------------------
# Save test vectors to CSV
# ------------------------------------------------------------
def save_csv(weights, codes, path="huffman_test_vectors.csv"):
    with open(path, "w", newline='') as f:
        writer = csv.writer(f)
        writer.writerow(["A","B","C","E","I","L","O","V",
                         "codebook", "ILOVE_bits", "ICLAB_bits"])
        cb = ";".join(f"{c}:{codes[c]}" for c in CHARS)
        writer.writerow(weights + [
            cb,
            encode_string("ILOVE", codes),
            encode_string("ICLAB", codes)
        ])
    print(f"[INFO] CSV saved to: {path}")


# ------------------------------------------------------------
# Main (local execution)
# ------------------------------------------------------------
if __name__ == "__main__":
    print("==============================================")
    print("  NYCU IC Lab06 – Huffman Golden Reference")
    print("==============================================\n")

    # Input weights
    print("Please enter 8 weights for A B C E I L O V:")
    print("Example: 5 9 12 13 16 45 2 7\n")

    # Parse input
    while True:
        try:
            arr = input("Enter weights: ").split()
            weights = list(map(int, arr))
            if len(weights) != 8:
                raise ValueError
            break
        except:
            print("Invalid input! Please input exactly 8 integers.")

    # Build Huffman
    codes, root = build_huffman_from_weights(weights)

    print("\n=== Huffman Codebook ===")
    for ch in CHARS:
        print(f"{ch}: {codes[ch]}")

    print("\nEncoded Outputs:")
    print("ILOVE:", encode_string("ILOVE", codes))
    print("ICLAB:", encode_string("ICLAB", codes))

    # Save CSV
    save_csv(weights, codes)
