import struct
import numpy as np
import random
import os

# ==========================================
# 參數設定
# ==========================================
PAT_NUM = 100
OUT_DIR = "../00_TESTBED/"

# 💡 分拆成 5 個獨立檔案
OPT_FILE = os.path.join(OUT_DIR, "opt.dat")
IMG_FILE = os.path.join(OUT_DIR, "img.dat")
KER_FILE = os.path.join(OUT_DIR, "kernel.dat")
WGT_FILE = os.path.join(OUT_DIR, "weight.dat")
GLD_FILE = os.path.join(OUT_DIR, "golden.dat")

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
            
        return act_out

    out0 = process_image(img0)
    out1 = process_image(img1)
    l1_dist = np.sum(np.abs(out0 - out1, dtype=np.float32), dtype=np.float32)
    return l1_dist

# ==========================================
# 產生檔案
# ==========================================
print(f"🚀 開始生成 {PAT_NUM} 筆測資 (拆分多檔案)...")

# 💡 同時開啟 5 個檔案寫入
with open(OPT_FILE, 'w') as f_opt, \
     open(IMG_FILE, 'w') as f_img, \
     open(KER_FILE, 'w') as f_ker, \
     open(WGT_FILE, 'w') as f_wgt, \
     open(GLD_FILE, 'w') as f_gld:
         
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
            
        golden_ans = golden_model(img0, img1, kernel, weight, opt)
        
        # 1. 寫入 Opt
        f_opt.write(f"{opt}\n")
        
        # 2. 寫入 Img (96 筆)
        for img in [img0, img1]:
            for c in range(3):
                for i in range(4):
                    for j in range(4):
                        f_img.write(f"{float_to_hex(img[i,j,c])}\n")
                        
        # 3. 寫入 Kernel (27 筆)
        for c in range(3):
            for i in range(3):
                for j in range(3):
                    f_ker.write(f"{float_to_hex(kernel[i,j,c])}\n")
                    
        # 4. 寫入 Weight (4 筆)
        weight_flat = weight.flatten()
        for w in weight_flat:
            f_wgt.write(f"{float_to_hex(w)}\n")
            
        # 5. 寫入 Golden Answer
        f_gld.write(f"{float_to_hex(golden_ans)}\n")

print(f"✅ 成功生成 5 個獨立的測資檔案至 {OUT_DIR}！")