import random

# 設定要產生幾個 Pattern (跟你 Verilog 的 PAT_NUM 一樣)
PAT_NUM = 10
FILE_NAME = "seeds.txt"

def generate_seeds():
    with open(FILE_NAME, "w") as f:
        for _ in range(PAT_NUM):
            # 產生 1 到 2^31-1 之間的隨機整數 (避免 0)
            rand_seed = random.randint(1, 2147483647)
            f.write(f"{rand_seed}\n")
    
    print(f"已成功產生 {FILE_NAME}，包含 {PAT_NUM} 個隨機數字。")

if __name__ == "__main__":
    generate_seeds()