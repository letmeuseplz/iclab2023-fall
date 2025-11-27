import numpy as np
import os

# ============================================================
# 固定 seed
# ============================================================
np.random.seed(1234)

# ============================================================
# 工具：float32 → IEEE754 Hex
# ============================================================
def float32_to_hex(f):
    return format(np.frombuffer(np.float32(f).tobytes(), dtype=np.uint32)[0], '08x')


# ============================================================
# 資料生成
# ============================================================
def gen_images():
    return np.random.uniform(low=-0.5, high=255.0, size=(2,4,4,3)).astype(np.float32)

def gen_kernel():
    return np.random.uniform(low=-0.5, high=0.5, size=(3,3,3)).astype(np.float32)

def gen_weight():
    return np.random.uniform(low=-0.5, high=0.5, size=(2,2)).astype(np.float32)


imgs = gen_images()
kernel = gen_kernel()
weight = gen_weight()


# ============================================================
# Padding
# ============================================================
def replication_pad(img):
    return np.pad(img, ((1,1),(1,1),(0,0)), mode='edge')

def zero_pad(img):
    return np.pad(img, ((1,1),(1,1),(0,0)), mode='constant')


# ============================================================
# Conv (cross-correlation)
# ============================================================
def conv2d_crosscorr(img, kernel):
    H, W, C = img.shape
    kh, kw, kc = kernel.shape
    outH = H - kh + 1
    outW = W - kw + 1
    out = np.zeros((outH, outW), dtype=np.float32)

    for i in range(outH):
        for j in range(outW):
            patch = img[i:i+kh, j:j+kw, :]
            out[i,j] = np.sum(patch * kernel)
    return out


# ============================================================
# Max pooling 2x2
# ============================================================
def max_pool_2x2(x):
    return np.max(x)


# ============================================================
# Min-max normalization
# ============================================================
def min_max_normalize(vec):
    mn, mx = vec.min(), vec.max()
    if np.isclose(mn, mx): return np.zeros_like(vec)
    return (vec - mn) / (mx - mn)


# ============================================================
# Activation
# ============================================================
sigmoid = lambda x: 1 / (1 + np.exp(-x))
tanh = lambda x: np.tanh(x)


# ============================================================
# 子網路完整流程
# ============================================================
def simulate(img, kernel, weight, pad_mode, act):
    padded = replication_pad(img) if pad_mode == "replication" else zero_pad(img)
    feat = conv2d_crosscorr(padded, kernel)
    pooled = max_pool_2x2(feat)
    fc = pooled * weight
    flat = fc.reshape(-1)
    norm = min_max_normalize(flat)

    act_fn = sigmoid if act == "sigmoid" else tanh
    enc = act_fn(norm).astype(np.float32)

    return enc


# ============================================================
# 選項組合
# ============================================================
opts = {
    0: ("sigmoid", "replication"),
    1: ("sigmoid", "zero"),
    2: ("tanh", "replication"),
    3: ("tanh", "zero"),
}


# ============================================================
# 建立輸出資料夾
# ============================================================
os.makedirs("gold_output", exist_ok=True)


# ============================================================
# RAW memory data 輸出
# ============================================================
with open("gold_output/image_data.mem", "w") as f:
    for v in imgs.reshape(-1):
        f.write("0x" + float32_to_hex(v) + "\n")

with open("gold_output/kernel_data.mem", "w") as f:
    for v in kernel.reshape(-1):
        f.write("0x" + float32_to_hex(v) + "\n")

with open("gold_output/weight_data.mem", "w") as f:
    for v in weight.reshape(-1):
        f.write("0x" + float32_to_hex(v) + "\n")


# ============================================================
# Gold patterns (enc1, enc2, L1)
# ============================================================
for opt in range(4):
    act, pad = opts[opt]
    enc1 = simulate(imgs[0], kernel, weight, pad, act)
    enc2 = simulate(imgs[1], kernel, weight, pad, act)
    L1 = np.sum(np.abs(enc1 - enc2))

    with open(f"gold_output/gold_opt{opt}.txt", "w") as f:
        f.write(f"OPT={opt} ({act},{pad})\n\n")

        f.write("=== enc1 ===\n")
        for v in enc1:
            f.write("0x" + float32_to_hex(v) + "\n")

        f.write("\n=== enc2 ===\n")
        for v in enc2:
            f.write("0x" + float32_to_hex(v) + "\n")

        f.write("\n=== L1 ===\n")
        f.write("0x" + float32_to_hex(np.float32(L1)) + "\n")

print("✨ Gold pattern generation done → gold_output/")
