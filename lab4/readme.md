2025/11/27 test the pattern 本lab意在完成SNN的架構 使用單一Buffer存取image的input


2025/12/05 大致完成 
1.在設計上假設所有ip都是組合邏輯(except the dw_exp)  
2.使用單一buffer來存取總共96個輸入 為了避免時序過長  在第16個點輸入之後開始做convolution
3.在convolution部分插入pipeline避免組合邏輯運算過長
4.conv,fc,act l1中共用加法器
5.conv fc中共用乘法器
6.pool act中共用比較器
7. act l1共用減法器
