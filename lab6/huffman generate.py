import heapq
import random
from itertools import count

# ==================================================
# Huffman Node (符合 PDF 規則)
# ==================================================
class Node:
    _ids = count(0)

    def __init__(self, weight, symbol=None, left=None, right=None, old=True):
        self.weight = weight
        self.symbol = symbol
        self.left = left
        self.right = right
        self.old = old
        self.id = next(Node._ids)

    def __lt__(self, other):
        # 1. weight 小的先
        if self.weight != other.weight:
            return self.weight < other.weight

        # 2. char priority (A > B > C > E > I > L > O > V)
        if self.symbol is not None and other.symbol is not None:
            return CHAR_PRI[self.symbol] < CHAR_PRI[other.symbol]

        # 3. old subtree > new subtree
        return self.old and not other.old


# ==================================================
# PDF 規定的字元 priority
# ==================================================
CHAR_ORDER = ["A","B","C","E","I","L","O","V"]
CHAR_PRI = {c: i for i, c in enumerate(CHAR_ORDER)}


# ==================================================
# Huffman build
# ==================================================
def build_huffman(weights):
    heap = []
    for sym, w in weights.items():
        heapq.heappush(heap, Node(w, symbol=sym))

    while len(heap) > 1:
        n1 = heapq.heappop(heap)
        n2 = heapq.heappop(heap)

        # bigger on left (0), smaller on right (1)
        if n1.weight < n2.weight:
            left, right = n2, n1
        else:
            left, right = n1, n2

        heapq.heappush(
            heap,
            Node(left.weight + right.weight,
                 left=left, right=right, old=False)
        )

    return heap[0]


# ==================================================
# Extract codes
# ==================================================
def get_codes(node, prefix="", table=None):
    if table is None:
        table = {}
    if node.symbol is not None:
        table[node.symbol] = prefix
    else:
        get_codes(node.left,  prefix + "0", table)
        get_codes(node.right, prefix + "1", table)
    return table


# ==================================================
# Generate patterns
# ==================================================
NUM_PATTERN = 200          # <<< 你可以改這個
WEIGHT_MIN = 1
WEIGHT_MAX = 7

random.seed(1234)

with open("input.txt", "w") as fin, open("golden.txt", "w") as fgold:
    for _ in range(NUM_PATTERN):

        # random weights
        wlist = [random.randint(WEIGHT_MIN, WEIGHT_MAX) for _ in range(8)]
        mode = random.randint(0, 1)

        weights = {CHAR_ORDER[i]: wlist[i] for i in range(8)}
        root = build_huffman(weights)
        codes = get_codes(root)

        # write input
        fin.write(" ".join(map(str, wlist)) + f" {mode}\n")

        # build output bitstream
        out = ""
        if mode == 0:
            for c in "ILOVE":
                out += codes[c]
        else:
            for c in "ICLAB":
                out += codes[c]

        fgold.write(out + "\n")
