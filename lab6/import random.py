import re

# =============================================================================
# 1. 基礎設定
# =============================================================================
CHAR_MAP = ['A', 'B', 'C', 'E', 'I', 'L', 'O', 'V']

# Mode 0: I L O V E (ID: 4, 5, 6, 7, 3)
# Mode 1: I C L A B (ID: 4, 2, 5, 0, 1)
MODE_STRING_IDS = {
    0: [4, 5, 6, 7, 3],
    1: [4, 2, 5, 0, 1]
}

class Node:
    def __init__(self, weight, id_num, left=None, right=None):
        self.weight = weight
        self.id = id_num
        self.left = left
        self.right = right

    def __repr__(self):
        return f"Node(w={self.weight}, id={self.id})"

# =============================================================================
# 2. 核心邏輯：依照你的敘述建樹
# =============================================================================
def build_huffman_tree_user_logic(weights):
    # 步驟 1: 初始化 Leaf Nodes (ID 0~7)
    nodes = []
    for i, w in enumerate(weights):
        nodes.append(Node(w, i))

    next_internal_id = 8  # Internal node ID 從 8 開始

    # 迴圈直到剩下一顆根節點
    while len(nodes) > 1:
        # A. 排序 (Sort)
        # 規則：權重由大到小 (Descending)，ID 由小到大 (Ascending)
        # 這樣 List 的尾端 (End) 就會是權重最小的
        # Python sort 是 Ascending，所以 key 設定：
        # weight 加負號變 Descending
        # id 保持正號變 Ascending
        # (x.weight, -x.id) 配合 reverse=True -> 權重(大->小), ID(小->大)
        
        # 讓我們用更直觀的寫法：
        # 先排 ID (小到大)，再排 Weight (大到小)
        # Python 的 sort 是穩定的，所以可以分兩次，或者用 tuple key
        # 我們希望 List 左邊是 大權重，右邊是 小權重
        # (7, 1) > (7, 7) ? 我們希望 (7, 1) 在前 (7, 7) 在後
        # Tuple比較: (7, -1) > (7, -7). True.
        
        nodes.sort(key=lambda x: (x.weight, -x.id), reverse=True)
        
        # 檢查用 (Debug): 印出排序結果，看是否符合你的 "b v c e o a i l"
        # print([f"{n.weight}({n.id})" for n in nodes])

        # B. 合併 (Merge)
        # 根據你的敘述： "w(o) > w(a) ... 所以 a 在右邊"
        # 在我們的排序中，a (3) 會排在 o (5) 的後面 (List 的最右邊)
        # 所以 pop() 出來的第一個是最右邊的元素 (Right Child)
        
        right_child = nodes.pop() # List 最後一個 (權重最小 / ID最大) -> 建 1
        left_child = nodes.pop()  # List 倒數第二個 (權重次小)       -> 建 0

        # C. 建立新節點
        new_w = left_child.weight + right_child.weight
        parent = Node(new_w, next_internal_id, left=left_child, right=right_child)
        
        # 放回 List 等待下一次 Sort
        nodes.append(parent)
        next_internal_id += 1

    return nodes[0]  # Root

# =============================================================================
# 3. 產生編碼表 (左0 右1)
# =============================================================================
def generate_codes(node, current_code="", table=None):
    if table is None:
        table = {}
    
    if node.left is None and node.right is None:
        table[node.id] = current_code
        return table

    if node.left:
        generate_codes(node.left, current_code + "0", table)
    if node.right:
        generate_codes(node.right, current_code + "1", table)
    
    return table

# =============================================================================
# 4. 檔案處理 (保持不變)
# =============================================================================
def process_files(input_file, output_file):
    try:
        with open(input_file, 'r') as f_in, open(output_file, 'w') as f_out:
            print(f"Processing {input_file}...")
            
            lines = f_in.readlines()
            valid_count = 0

            for line in lines:
                numbers = [int(n) for n in re.findall(r'\d+', line)]

                if len(numbers) < 9:
                    continue

                data = numbers[-9:]
                weights = data[0:8]
                mode = data[8]

                # 1. 建樹 (使用新的邏輯)
                root = build_huffman_tree_user_logic(weights)
                
                # 2. 產表
                code_table = generate_codes(root)
                
                # 3. 輸出
                target_ids = MODE_STRING_IDS[mode]
                bitstream = ""
                for char_id in target_ids:
                    bitstream += code_table[char_id]

                f_out.write(bitstream + "\n")
                valid_count += 1

            print(f"Done! Processed {valid_count} valid patterns.")
            print(f"Golden file generated at: {output_file}")

    except FileNotFoundError:
        print(f"Error: {input_file} not found.")

if __name__ == "__main__":
    process_files("input.txt", "golden.txt")