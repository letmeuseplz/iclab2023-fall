2025/11/27 test the pattern 本lab意在完成SNN的架構 使用單一Buffer存取image的input


2025/12/05 大致完成 
1.在設計上假設所有ip都是組合邏輯(except the dw_exp)  
2.使用單一buffer來存取總共96個輸入 為了避免時序過長  在第16個點輸入之後開始做convolution
3.在convolution部分插入pipeline避免組合邏輯運算過長
4.conv,fc,act l1中共用加法器
5.conv fc中共用乘法器
6.pool act中共用比較器
7. act l1共用減法器


In the Convolution (CONV) stage, the operation is not completed in a single clock cycle. Due to the requirement for Floating-Point (FP) precision, I utilized specialized IPs. To handle the padding requirements, instead of using a $6 \times 6$ buffer to store the entire padded result before performing Multiply-Accumulate (MAC) operations, I implemented a sliding window approach.Implementation Details:Window Logic: The system dynamically fetches 9 neighboring pixels for the current window. It performs Zero/Replicate padding logic on-the-fly to determine whether to output a zero or calculate the specific source address of a neighboring pixel.Pipelining for Timing Closure: To prevent excessively long combinational logic paths and ensure timing requirements are met, I implemented a multi-cycle pipeline:Cycle 1 (Address Calculation/Padding): Performs boundary checks and determines the correct pixel address or zero-padding value.Cycle 2 (Multiplication): Data is fed into the multipliers.Cycle 3 (Addition/Accumulation): The products are sent to the adder tree to produce the final output.
