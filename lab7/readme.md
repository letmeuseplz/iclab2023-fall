1.這個lab練習三個跨時鐘的資料傳輸問題  用到handshake synchronizer   asynchronize fifo  跨時領域中 會有亞穩態 (Metastability)情況，透過NDFF可以使取值穩定下來，一般插入兩級，但要依據是從塊到慢或是慢到快再評估。handshake相當於是mux syn概念 這裡用來處理取32bits seed跨時脈  而asyn fifo來處理多筆資料的傳輸
2.This lab focuses on addressing data transfer challenges across three different clock domains, utilizing Handshake Synchronizers and Asynchronous FIFOs.

1. Metastability and Synchronization
When signals cross clock domains, metastability can occur. To mitigate this, I implemented NDFF (N-stage D Flip-Flop) synchronizers to stabilize the sampled values. While a 2-stage synchronizer is the standard implementation, the specific synchronization strategy (such as the number of stages or the need for additional logic) must be evaluated based on whether the data is moving from a Fast-to-Slow or Slow-to-Fast clock domain.

2. Handshake Synchronizer
The handshake synchronizer functions similarly to a MUX-based synchronizer. In this design, I utilized the handshake protocol to securely transfer a 32-bit seed across clock domains, ensuring that the destination domain only samples the data once it has stabilized and the "Ready/Valid" state is confirmed.

3. Asynchronous FIFO
For scenarios involving the transfer of multiple data packets (burst data), I implemented an Asynchronous FIFO. This approach manages the pointer synchronization using Gray codes to prevent errors, effectively handling the throughput difference between the disparate clock domains.
