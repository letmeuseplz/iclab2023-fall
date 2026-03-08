import struct
import numpy as np
import random
import os

# ==========================================
# 參數設定
# ==========================================
PAT_NUM = 30
OUT_DIR = "../00_TESTBED/"

# 💡 分拆成多個獨立檔案 (包含輸入測資與所有檢查點)
OPT_FILE = os.path.join(OUT_DIR, "opt.dat")
IMG_FILE = os.path.join(OUT_DIR, "img.dat")
KER_FILE = os.path.join(OUT_DIR, "kernel.dat")
WGT_FILE = os.path.join(OUT_DIR, "weight.dat")
GLD_FILE = os.path.join(OUT_DIR, "golden.dat")

# 檢查點檔案 (Checkpoints)
CHK_CONV_FILE = os.path.join(OUT_DIR, "golden_conv.dat")
CHK_EQ_FILE   = os.path.join(OUT_DIR, "golden_eq.dat")
CHK_POOL_FILE = os.path.join(OUT_DIR, "golden_pool.dat")
CHK_FC_FILE   = os.path.join(OUT_DIR, "golden_fc.dat")
CHK_NORM_FILE = os.path.join(OUT_DIR, "golden_norm.dat")
CHK_ACT_FILE  = os.path.join(OUT_DIR, "golden_act.dat")

os.makedirs(OUT_DIR, exist_ok=True)

# ==========================================
# IEEE-754 Float <-> Hex 轉換工具
# ==========================================
def float_to_hex(f):
    f_32 = np.float32(f)
    return hex(struct.unpack('<I', struct.pack('<f', f_32))[0])[2:].zfill(8)

# ==========================================
# SNN 軟體黃金模型 (符合 Lab04 & Lab08)
# ==========================================
def padding_2d(img, pad_type):
    if img.ndim == 3:
        if pad_type == 1: # Zero
            return np.pad(img, pad_width=((1,1), (1,1), (0,0)), mode='constant', constant_values=0)
        else:             # Replication
            return np.pad(img, pad_width=((1,1), (1,1), (0,0)), mode='edge')
    else:
        if pad_type == 1: # Zero
            return np.pad(img, pad_width=1, mode='constant', constant_values=0)
        else:             # Replication
            return np.pad(img, pad_width=1, mode='edge')

def golden_model(img0, img1, kernel, weight, opt):
    pad_type = opt % 2 
    act_type = opt // 2 
    
    def process_image(img):
        # 1. Conv
        padded_img = padding_2d(img, pad_type)
        conv_out = np.zeros((4, 4), dtype=np.float32)
        for c in range(3):
            for i in range(4):
                for j in range(4):
                    window = padded_img[i:i+3, j:j+3, c]
                    conv_out[i,j] += np.sum(window * kernel[:,:,c], dtype=np.float32)
                    
        # 2. Equalization
        eq_out = np.zeros((4, 4), dtype=np.float32)
        padded_eq = padding_2d(conv_out, pad_type)
        for i in range(4):
            for j in range(4):
                window = padded_eq[i:i+3, j:j+3]
                eq_out[i,j] = np.sum(window, dtype=np.float32) / np.float32(9.0)
                
        # 3. Max Pooling
        pool_out = np.zeros((2, 2), dtype=np.float32)
        for i in range(2):
            for j in range(2):
                pool_out[i,j] = np.max(eq_out[i*2:i*2+2, j*2:j*2+2])
                
        # 4. FC (矩陣乘法)
        fc_mat = np.matmul(pool_out, weight, dtype=np.float32)
        fc_out = fc_mat.flatten()
        
        # 5. Normalization
        f_max = np.max(fc_out)
        f_min = np.min(fc_out)
        denom = f_max - f_min
        if denom == np.float32(0.0):
            norm_out = np.zeros_like(fc_out, dtype=np.float32)
        else:
            norm_out = (fc_out - f_min) / denom
            
        # 6. Activation
        if act_type == 0:
            act_out = np.float32(1.0) / (np.float32(1.0) + np.exp(-norm_out, dtype=np.float32))
        else:             
            act_out = np.tanh(norm_out, dtype=np.float32)
            
        # 💡 將所有中間結果打包回傳
        checkpoints = {
            'conv': conv_out,
            'eq': eq_out,
            'pool': pool_out,
            'fc': fc_out,
            'norm': norm_out,
            'act': act_out
        }
        return act_out, checkpoints

    out0, chk0 = process_image(img0)
    out1, chk1 = process_image(img1)
    l1_dist = np.sum(np.abs(out0 - out1, dtype=np.float32), dtype=np.float32)
    
    return l1_dist, chk0, chk1

# ==========================================
# 輔助寫檔函數 (自動攤平並加上註解)
# ==========================================
def write_checkpoint(f, arr, prefix):
    arr_flat = arr.flatten()
    for idx, val in enumerate(arr_flat):
        f.write(f"{float_to_hex(val)} // {prefix}[{idx}]: {val:.6f}\n")

# ==========================================
# 產生檔案
# ==========================================
print(f"🚀 開始生成 {PAT_NUM} 筆測資與所有檢查點檔案...")

# 同時開啟所有要寫入的檔案
with open(OPT_FILE, 'w') as f_opt, \
     open(IMG_FILE, 'w') as f_img, \
     open(KER_FILE, 'w') as f_ker, \
     open(WGT_FILE, 'w') as f_wgt, \
     open(GLD_FILE, 'w') as f_gld, \
     open(CHK_CONV_FILE, 'w') as f_c_conv, \
     open(CHK_EQ_FILE, 'w') as f_c_eq, \
     open(CHK_POOL_FILE, 'w') as f_c_pool, \
     open(CHK_FC_FILE, 'w') as f_c_fc, \
     open(CHK_NORM_FILE, 'w') as f_c_norm, \
     open(CHK_ACT_FILE, 'w') as f_c_act:
         
    for pat in range(PAT_NUM):
        opt = random.randint(0, 3)
        img0 = np.random.uniform(0.5, 255.0, (4, 4, 3)).astype(np.float32)
        img1 = np.random.uniform(0.5, 255.0, (4, 4, 3)).astype(np.float32)
        kernel = np.random.uniform(0.0, 0.5, (3, 3, 3)).astype(np.float32)
        weight = np.random.uniform(0.0, 0.5, (2, 2)).astype(np.float32)
        
        # Corner Case
        if pat % 10 == 9:
            val = np.random.uniform(0.5, 255.0)
            img0 = np.full((4, 4, 3), val, dtype=np.float32)
            kernel = np.full((3, 3, 3), 0.1, dtype=np.float32) 
            
        # 取得最終答案與檢查點
        golden_ans, chk0, chk1 = golden_model(img0, img1, kernel, weight, opt)
        
        # --- 寫入輸入測資 ---
        f_opt.write(f"{opt} // Option: {opt}\n")
        
        for img_idx, img in enumerate([img0, img1]):
            for c in range(3):
                for i in range(4):
                    for j in range(4):
                        val = img[i,j,c]
                        f_img.write(f"{float_to_hex(val)} // pat{pat}_img{img_idx}[{i},{j},c{c}]: {val:.6f}\n")
                        
        for c in range(3):
            for i in range(3):
                for j in range(3):
                    val = kernel[i,j,c]
                    f_ker.write(f"{float_to_hex(val)} // pat{pat}_kernel[{i},{j},c{c}]: {val:.6f}\n")
                    
        weight_flat = weight.flatten()
        for idx, w in enumerate(weight_flat):
            f_wgt.write(f"{float_to_hex(w)} // pat{pat}_weight[{idx}]: {w:.6f}\n")
            
        f_gld.write(f"{float_to_hex(golden_ans)} // pat{pat}_golden_L1_dist: {golden_ans:.6f}\n")

        # --- 💡 寫入中間檢查點 ---
        # 每個 pattern 會有 img0 和 img1 兩次計算，這裡照順序寫入檔案
        for img_idx, chk in enumerate([chk0, chk1]):
            prefix = f"pat{pat}_img{img_idx}"
            
            # 1. Conv (4x4 = 16 筆)
            write_checkpoint(f_c_conv, chk['conv'], f"{prefix}_conv")
            # 2. Equalization (4x4 = 16 筆)
            write_checkpoint(f_c_eq,   chk['eq'],   f"{prefix}_eq")
            # 3. Max Pooling (2x2 = 4 筆)
            write_checkpoint(f_c_pool, chk['pool'], f"{prefix}_pool")
            # 4. FC (1x4 = 4 筆)
            write_checkpoint(f_c_fc,   chk['fc'],   f"{prefix}_fc")
            # 5. Normalization (1x4 = 4 筆)
            write_checkpoint(f_c_norm, chk['norm'], f"{prefix}_norm")
            # 6. Activation (1x4 = 4 筆)
            write_checkpoint(f_c_act,  chk['act'],  f"{prefix}_act")

print(f"✅ 成功生成輸入測資及 6 個階段的 Checkpoint 檔案至 {OUT_DIR}！")