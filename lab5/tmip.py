import numpy as np
from scipy.ndimage import median_filter
import random
import os

def generate_pattern(pat_idx):
    print(f"========== Generating Pattern {pat_idx} ==========")
    
    # 1. 隨機生成初始測資
    size_idx = random.randint(0, 2)
    dim = {0: 4, 1: 8, 2: 16}[size_idx]
    
    R = np.random.randint(0, 256, (dim, dim), dtype=np.uint8)
    G = np.random.randint(0, 256, (dim, dim), dtype=np.uint8)
    B = np.random.randint(0, 256, (dim, dim), dtype=np.uint8)
    template = np.random.randint(0, 256, (3, 3), dtype=np.uint8)
    
    # 分開儲存各類資料
    img_data = [size_idx]
    tpl_data = []
    act_data = []
    golden_data = []
    
    # R, G, B 交錯排列 (Raster scan)
    for i in range(dim):
        for j in range(dim):
            img_data.extend([R[i, j], G[i, j], B[i, j]])
            
    tpl_data.extend(template.flatten().tolist())
    
    current_img = np.zeros((dim, dim), dtype=np.uint32)
    
    # 2. 生成 8 個 Set
    for set_idx in range(8):
        print(f"--- Set {set_idx} ---")
        num_actions = random.randint(2, 8)
        act_first = random.randint(0, 2)
        act_last = 7
        act_mid = [random.randint(3, 6) for _ in range(num_actions - 2)]
        actions = [act_first] + act_mid + [act_last]
        
        # 寫入 Action 數量與內容
        act_data.append(num_actions)
        act_data.extend(actions)
        print(f"Actions: {actions}")
        
        # 3. 執行演算法
        for act in actions:
            if act == 0:   # Gray Max
                current_img = np.maximum(np.maximum(R, G), B).astype(np.uint32)
            elif act == 1: # Gray Avg
                current_img = ((R.astype(np.uint32) + G + B) // 3)
            elif act == 2: # Gray Weighted
                current_img = (R.astype(np.uint32)//4 + G.astype(np.uint32)//2 + B.astype(np.uint32)//4)
            elif act == 3: # Max Pooling
                curr_dim = current_img.shape[0]
                if curr_dim > 4:
                    # 2x2 stride 2 Max Pooling
                    current_img = current_img.reshape(curr_dim//2, 2, curr_dim//2, 2).max(axis=(1, 3))
            elif act == 4: # Negative
                current_img = 255 - current_img
            elif act == 5: # Horizontal Flip
                current_img = np.fliplr(current_img)
            elif act == 6: # Median Filter (Replication Padding)
                current_img = median_filter(current_img, size=3, mode='nearest')
            elif act == 7: # Cross Correlation (Zero Padding)
                curr_dim = current_img.shape[0]
                padded_img = np.pad(current_img, pad_width=1, mode='constant', constant_values=0)
                out_img = np.zeros((curr_dim, curr_dim), dtype=np.uint32)
                for i in range(curr_dim):
                    for j in range(curr_dim):
                        window = padded_img[i:i+3, j:j+3]
                        out_img[i, j] = np.sum(window * template)
                current_img = out_img
                
        # 顯示該 Set 的結果
        flat_result = current_img.flatten().tolist()
        # ★ 關鍵修正：先寫入預期輸出的數量，再寫入答案
        golden_data.append(len(flat_result)) 
        golden_data.extend(flat_result)
        
    return img_data, tpl_data, act_data, golden_data

def main():
    num_patterns = 200
    
    all_imgs, all_tpls, all_acts, all_goldens = [], [], [], []
    
    for p in range(num_patterns):
        img, tpl, act, gld = generate_pattern(p)
        all_imgs.extend(img)
        all_tpls.extend(tpl)
        all_acts.extend(act)
        all_goldens.extend(gld)
        
    # 確保資料夾存在 (對應 Verilog 的相對路徑)
    os.makedirs("../00_TESTBED", exist_ok=True)
        
    # 分別輸出給 Verilog $fscanf 讀取的檔案
    with open("../00_TESTBED/img.dat", "w") as f:
        for val in all_imgs: f.write(f"{val}\n")
            
    with open("../00_TESTBED/template.dat", "w") as f:
        for val in all_tpls: f.write(f"{val}\n")
            
    with open("../00_TESTBED/action.dat", "w") as f:
        for val in all_acts: f.write(f"{val}\n")
            
    with open("../00_TESTBED/golden.dat", "w") as f:
        for val in all_goldens: f.write(f"{val}\n")
            
    print(f"\n[Success] Generated {num_patterns} patterns.")
    print("Files 'img.dat', 'template.dat', 'action.dat', and 'golden.dat' are ready!")

if __name__ == "__main__":
    main()