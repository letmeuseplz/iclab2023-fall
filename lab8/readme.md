1. 硬體架構優化：資源共享與低功耗運算乘法器資源共用 (Hardware Sharing)：針對新增的 Equalization 功能，不使用昂貴的除法器，改以乘法運算達成 。運算順序優化：在卷積層與 Equalization 階段，採用 「先加再乘」 的運算架構，大幅減少乘法器元件數量，進而降低動態功耗 (Dynamic Power) 與電路面積。精準度控制：運算過程嚴格遵守 IEEE-754 浮點數格式，確保輸出誤差控制在 0.01 以下 。
2. 時脈閘控技術 (Integrated Clock Gating, ICG)閘控策略：利用 cg_en 訊號實作細粒度的時脈閘控，在非運算狀態下關閉各處理模組的時脈 。暫存器穩定性優化：特別針對 Buffer 與控制訊號 (Control Signals) 的重置 (Reset) 邏輯進行設計，避免 Reset 與 Clock Gating 邏輯衝突，確保資料更新在各種狀態切換下皆能維持正確性。


 
