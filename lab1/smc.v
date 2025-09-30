module SMC(
	// Input Ports
	mode,
	W_0, V_GS_0, V_DS_0,
	W_1, V_GS_1, V_DS_1,
	W_2, V_GS_2, V_DS_2,
	W_3, V_GS_3, V_DS_3,
	W_4, V_GS_4, V_DS_4,
	W_5, V_GS_5, V_DS_5,
	// Output Ports
	out_n
);

//==============================================//
//          Input & Output Declaration          //
//==============================================//
input [2:0] W_0, V_GS_0, V_DS_0;
input [2:0] W_1, V_GS_1, V_DS_1;
input [2:0] W_2, V_GS_2, V_DS_2;
input [2:0] W_3, V_GS_3, V_DS_3;
input [2:0] W_4, V_GS_4, V_DS_4;
input [2:0] W_5, V_GS_5, V_DS_5;
input [1:0] mode;
output reg [7:0] out_n;   
reg [7:0] tmp;
reg [8:0] t[0:5];     
//================================================================
//    DESIGN
//================================================================
wire [8:0] Id_gm_0, Id_gm_1, Id_gm_2, Id_gm_3, Id_gm_4, Id_gm_5; // maby 6-bits is ok
ID_gm_Calculation CAL0(.W(W_0), .mode(mode[0]), .V_GS(V_GS_0), .V_DS(V_DS_0), .ID_gm(Id_gm_0));
ID_gm_Calculation CAL1(.W(W_1), .mode(mode[0]), .V_GS(V_GS_1), .V_DS(V_DS_1), .ID_gm(Id_gm_1));
ID_gm_Calculation CAL2(.W(W_2), .mode(mode[0]), .V_GS(V_GS_2), .V_DS(V_DS_2), .ID_gm(Id_gm_2));
ID_gm_Calculation CAL3(.W(W_3), .mode(mode[0]), .V_GS(V_GS_3), .V_DS(V_DS_3), .ID_gm(Id_gm_3));
ID_gm_Calculation CAL4(.W(W_4), .mode(mode[0]), .V_GS(V_GS_4), .V_DS(V_DS_4), .ID_gm(Id_gm_4));
ID_gm_Calculation CAL5(.W(W_5), .mode(mode[0]), .V_GS(V_GS_5), .V_DS(V_DS_5), .ID_gm(Id_gm_5));


always @(*) begin
    t[0] = Id_gm_0;
    t[1] = Id_gm_1;
    t[2] = Id_gm_2;
    t[3] = Id_gm_3;
    t[4] = Id_gm_4;
    t[5] = Id_gm_5;

if (t[0] < t[5]) begin tmp = t[0]; t[0] = t[5]; t[5] = tmp; end
if (t[1] < t[3]) begin tmp = t[1]; t[1] = t[3]; t[3] = tmp; end
if (t[2] < t[4]) begin tmp = t[2]; t[2] = t[4]; t[4] = tmp; end

        // Stage 2
if (t[0] < t[2]) begin tmp = t[0]; t[0] = t[2]; t[2] = tmp; end
if (t[1] < t[4]) begin tmp = t[1]; t[1] = t[4]; t[4] = tmp; end
if (t[3] < t[5]) begin tmp = t[3]; t[3] = t[5]; t[5] = tmp; end

        // Stage 3
if (t[0] < t[1]) begin tmp = t[0]; t[0] = t[1]; t[1] = tmp; end
if (t[2] < t[3]) begin tmp = t[2]; t[2] = t[3]; t[3] = tmp; end
if (t[4] < t[5]) begin tmp = t[4]; t[4] = t[5]; t[5] = tmp; end

        // Stage 4
if (t[1] < t[2]) begin tmp = t[1]; t[1] = t[2]; t[2] = tmp; end
if (t[3] < t[4]) begin tmp = t[3]; t[3] = t[4]; t[4] = tmp; end

        // Stage 5
if (t[2] < t[3]) begin tmp = t[2]; t[2] = t[3]; t[3] = tmp; end

if(mode) begin  //max
	t[0] = t[0];
	t[1] = t[1];
	t[2] = t[2];
end
	else begin  //min
	t[0] = t[5];
	t[1] = t[4];
	t[2] = t[3];
end
    end
wire [7:0] n_0 = t[0]/3;
wire [7:0] n_1 = t[1]/3;
wire [7:0] n_2 = t[2]/3;


always@(*)begin
    if(mode[0])
         out_n = (3*n_0 + 4*n_1 + 5*n_2 ) / 12;
    else
         out_n = (n_0 + n_1 + n_2) / 3;
end
endmodule
