//////////////////////////////////////////////////////////////////////////////////
// ID = 1/3 {W [ A ] } 
// if Triode A = 2(V_GS-1) - V_DS^2 , if Saturation A = (V_GS-1)^2
// gm = 2/3 {W [B]}
//if Triode B = V_DS , if Saturation B = (V_GS - 1)
//this module just return A or B
//////////////////////////////////////////////////////////////////////////////////
module ID_gm_Calculation(
    W,
    mode,
    V_GS,
    V_DS,
    ID_gm
    );
input mode; // mode:0  transconductance , mode :1 current
input [2:0] V_GS, V_DS, W;
output reg [8:0] ID_gm;
//================================================================
//    DESIGN
//================================================================
wire [2:0] minus1 = V_GS - 1;
wire Sat = (minus1 > V_DS)? 1 : 0; // 1:Triode mode  0:Saturation mode

wire [5:0] value = (Sat)? V_DS*V_DS : minus1 * minus1;


reg [5:0] ID_temp,gm_temp;
always @(*)begin
        if(Sat)begin
            gm_temp = 2 * V_DS;
        
            ID_temp = 2 * minus1*V_DS-value;
        end
        else begin 
            gm_temp = 2 * minus1;
            ID_temp = value;
        end
end
always@(*)begin
    if(mode)
        ID_gm = ID_temp * W;
    else
        ID_gm = gm_temp * W;   
end

endmodule