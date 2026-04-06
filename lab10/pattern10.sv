program automatic PATTERN(input clk, INF.PATTERN inf);
    import usertype::*;

  
    logic [7:0] golden_dram [0:8191]; 
   
    Error_Msg expected_err_msg;
    logic expected_complete;

    class random_data;
        rand Action act;
        rand Beverage_Type type;
        rand Beverage_Size size;
        rand Date date;
        rand logic [7:0] box_no;
      
        rand logic [7:0] box_sup[0:3]; 


     
        constraint limit_date {
            date.M inside {[1:12]};
            if (date.M == 2) {
                date.D inside {[1:28]}; // 假設今年非閏年
            } else if (date.M == 4 || date.M == 6 || date.M == 9 || date.M == 11) {
                date.D inside {[1:30]};
            } else {
                date.D inside {[1:31]};
            }
        }
        
    // 1. 稍微提高 Supply 的機率，以容易觸發 Ing_OF
        constraint act_dist {
            act dist { Make_drink := 40, Supply := 30, Check_Valid_Date := 30 };
        }
        
    
        constraint date_dist {
            date.M dist { [1:10] :/ 45, [11:12] :/ 55 }; 
        }

        // 3. 讓補貨量有時極大，容易觸發 Ing_OF
        constraint sup_dist {
            foreach(box_sup[i]) {
                box_sup[i] dist { [0:2000] :/ 50, [2000:4095] :/ 50 }; // 一半機率補一點點，一半機率爆補
            }
        }
    endclass

    random_data pat = new(); 


    // MAIN
    initial begin
      
        inf.rst_n = 1'b1;
        inf.sel_action_valid = 1'b0;
        inf.type_valid = 1'b0;
        inf.size_valid = 1'b0;
        inf.date_valid = 1'b0;
        inf.box_no_valid = 1'b0;
        inf.box_sup_valid = 1'b0;
        

        $readmemh("dram.dat", golden_dram);

        reset_task();

      
        for (int i = 0; i < 3000; i++) begin
            generate_and_drive_task();
            calculate_golden_task();   
            wait_and_check_task();   
        end

     
        $display("Congratulations");
        $finish;
    end


    task reset_task();
        inf.rst_n = 1'b1;
        #(10) inf.rst_n = 1'b0;
        #(10) inf.rst_n = 1'b1;
    endtask






    task generate_and_drive_task();
        pat.randomize(); 
        
        
        repeat($urandom_range(1, 4)) @(negedge clk);
        
       
        inf.sel_action_valid = 1'b1;
        inf.D = pat.act;
        @(negedge clk);
        inf.sel_action_valid = 1'b0;

     
        if (pat.act == Make_drink) begin
            repeat($urandom_range(1, 4)) @(negedge clk);
            inf.type_valid = 1'b1;
            inf.D = pat.type;
            @(negedge clk);
            inf.type_valid = 1'b0;
            
            repeat($urandom_range(1, 4)) @(negedge clk);
            inf.size_valid = 1'b1;
            inf.D = pat.size;
            @(negedge clk);
            inf.size_valid = 1'b0;
            
            repeat($urandom_range(1, 4)) @(negedge clk);
            inf.date_valid = 1'b1;
            inf.D = pat.date;
            @(negedge clk);
            inf.date_valid = 1'b0;
            
            repeat($urandom_range(1, 4)) @(negedge clk);
            inf.box_no_valid = 1'b1;
            inf.D = pat.box_no;
            @(negedge clk);
            inf.box_no_valid = 1'b0;
        end 
        
       else if (pat.act == Supply) begin
          
            repeat($urandom_range(1, 4)) @(negedge clk);
            inf.date_valid = 1'b1;
            inf.D = pat.date;
            @(negedge clk);
            inf.date_valid = 1'b0;
            
      
            repeat($urandom_range(1, 4)) @(negedge clk);
            inf.box_no_valid = 1'b1;
            inf.D = pat.box_no;      
            @(negedge clk);
            inf.box_no_valid = 1'b0; 

          
            for (int i = 0; i < 4; i++) begin
                repeat($urandom_range(1, 4)) @(negedge clk);
                inf.box_sup_valid = 1'b1;
                inf.D = pat.box_sup[i]; 
                @(negedge clk);
                inf.box_sup_valid = 1'b0;
            end
        end 
        
        else if (pat.act == Check_Valid_Date) begin
    
            repeat($urandom_range(1, 4)) @(negedge clk);
            inf.date_valid = 1'b1;
            inf.D = pat.date;
            @(negedge clk);
            inf.date_valid = 1'b0;
            

            repeat($urandom_range(1, 4)) @(negedge clk);
            inf.box_no_valid = 1'b1;
            inf.D = pat.box_no;
            @(negedge clk);
            inf.box_no_valid = 1'b0;
        end
    endtask



    task calculate_golden_task();
       
        logic [63:0] current_data;
        logic [11:0] d_bt, d_gt, d_m, d_p;
        logic [7:0]  d_exp_m, d_exp_d;
        logic is_exp;
        
        int vol;
        int req_bt, req_gt, req_m, req_p;
        int rem_bt, rem_gt, rem_m, rem_p;
        logic is_short;
        
        int add_bt, add_gt, add_m, add_p;
        logic is_of;
        
        int base_addr; 


        base_addr = pat.box_no * 8; 
        
    
        current_data = {golden_dram[base_addr+7], golden_dram[base_addr+6], 
                        golden_dram[base_addr+5], golden_dram[base_addr+4], 
                        golden_dram[base_addr+3], golden_dram[base_addr+2], 
                        golden_dram[base_addr+1], golden_dram[base_addr+0]};
                        
       
        {d_bt, d_gt, d_exp_m, d_m, d_p, d_exp_d} = current_data;


        is_exp = (pat.date.M > d_exp_m) || ((pat.date.M == d_exp_m) && (pat.date.D > d_exp_d));


        expected_err_msg = No_Err; 
        expected_complete = 1'b0;

        if (pat.act == Make_drink) begin
   
            if (pat.size == 2'b00) vol = 960; 
            else if (pat.size == 2'b01) vol = 720; 
            else vol = 480;

            req_bt = 0; req_gt = 0; req_m = 0; req_p = 0;
            case (pat.type)
                3'd0: req_bt = vol;                                    
                3'd1: begin req_bt = (vol/4)*3; req_m = (vol/4); end    
                3'd2: begin req_bt = (vol/2); req_m = (vol/2); end     
                3'd3: req_gt = vol;                                   
                3'd4: begin req_gt = (vol/2); req_m = (vol/2); end      
                3'd5: req_p  = vol;                                     
                3'd6: begin req_bt = (vol/2); req_p = (vol/2); end      
                3'd7: begin req_bt = (vol/2); req_m = (vol/4); req_p = (vol/4); end 
            endcase

            rem_bt = d_bt - req_bt;
            rem_gt = d_gt - req_gt;
            rem_m  = d_m  - req_m;
            rem_p  = d_p  - req_p;
            
            is_short = (rem_bt < 0) || (rem_gt < 0) || (rem_m < 0) || (rem_p < 0);

  
            if (is_exp) begin
                expected_err_msg = No_Exp;
                expected_complete = 1'b0;
            end 
            else if (is_short) begin
                expected_err_msg = No_Ing;
                expected_complete = 1'b0;
            end 
            else begin
                expected_err_msg = No_Err;
                expected_complete = 1'b1;
                
                
                current_data = {rem_bt[11:0], rem_gt[11:0], d_exp_m, rem_m[11:0], rem_p[11:0], d_exp_d};
                
                {golden_dram[base_addr+7], golden_dram[base_addr+6], 
                 golden_dram[base_addr+5], golden_dram[base_addr+4], 
                 golden_dram[base_addr+3], golden_dram[base_addr+2], 
                 golden_dram[base_addr+1], golden_dram[base_addr+0]} = current_data;
            end
        end

        else if (pat.act == Supply) begin

            add_bt = d_bt + pat.box_sup[0];
            add_gt = d_gt + pat.box_sup[1];
            add_m  = d_m  + pat.box_sup[2];
            add_p  = d_p  + pat.box_sup[3];

            is_of = (add_bt > 4095) || (add_gt > 4095) || (add_m > 4095) || (add_p > 4095);

            if (is_of) begin
                expected_err_msg = Ing_OF;
                expected_complete = 1'b0;
            end 
            else begin
                expected_err_msg = No_Err;
                expected_complete = 1'b1;
            end


            add_bt = (add_bt > 4095) ? 4095 : add_bt;
            add_gt = (add_gt > 4095) ? 4095 : add_gt;
            add_m  = (add_m  > 4095) ? 4095 : add_m;
            add_p  = (add_p  > 4095) ? 4095 : add_p;

            // 打包新資料 (注意日期要換成 pattern 給的進貨日期)
            current_data = {add_bt[11:0], add_gt[11:0], pat.date.M, add_m[11:0], add_p[11:0], pat.date.D};
            
            {golden_dram[base_addr+7], golden_dram[base_addr+6], 
             golden_dram[base_addr+5], golden_dram[base_addr+4], 
             golden_dram[base_addr+3], golden_dram[base_addr+2], 
             golden_dram[base_addr+1], golden_dram[base_addr+0]} = current_data;
        end

        else if (pat.act == Check_Valid_Date) begin
            if (is_exp) begin
                expected_err_msg = No_Exp;
                expected_complete = 1'b0;
            end else begin
                expected_err_msg = No_Err;
                expected_complete = 1'b1;
            end
        end
    endtask

    task wait_and_check_task();
            int wait_cycles = 0;
            
            while(inf.out_valid === 1'b0) begin
                wait_cycles++;
                if (wait_cycles > 1000) begin
                    $display("Wrong Answer"); 
                    $finish;
                end
                @(negedge clk);
            end
          
            if (inf.err_msg !== expected_err_msg || inf.complete !== expected_complete) begin
                $display("Wrong Answer"); // [cite: 39]
                $finish;
            end
        endtask
endprogram 