import sys

def generate_golden():
    # 根據 Spec 定義 Xorshift 參數 [cite: 59]
    a, b, c = 13, 17, 5
    
    # 你提供的 10 組 Seed [cite: 135]
    seeds = [12345, 67890, 13579, 24680, 11223, 44556, 99887, 77665, 33221, 55443]
    
    # 用來存放所有結果的列表
    all_results = []

    for s in seeds:
        x = s & 0xFFFFFFFF  # 確保初始 Seed 是 32-bit [cite: 135]
        
        # 每組 Seed 產生 256 個隨機數 [cite: 17, 139]
        for _ in range(256):
            # 依照 Spec 步驟進行 Xorshift 運算 [cite: 44, 48, 51, 53]
            # 步驟 i: X = X ^ (X << a)
            x = (x ^ (x << a)) & 0xFFFFFFFF
            # 步驟 ii: X = X ^ (X >> b)
            x = (x ^ (x >> b)) & 0xFFFFFFFF
            # 步驟 iii: X = X ^ (X << c)
            x = (x ^ (x << c)) & 0xFFFFFFFF
            
            all_results.append(x)

    # 將結果寫入檔案，方便 Verilog 用 $readmemh 讀取
    try:
        with open("golden_data.txt", "w") as f:
            for val in all_results:
                # 輸出成 8 位數的 16 進位格式 (不加 0x)
                f.write(f"{val:08X}\n")
        print(f"成功！已產生 {len(all_results)} 筆資料並存入 golden_data.txt")
    except IOError as e:
        print(f"檔案寫入失敗: {e}")

if __name__ == "__main__":
    generate_golden()


