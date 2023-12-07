/*  ASTECAS projet
*   CINVESTAV-GLD
*/
module OQPSK_PS_RCOSINE2
#(parameter 
DW_IN 		= 13, 	// Output bits
I_SEL 		= 01,	// Integer bits
SAMPLES 		= 02,	// Samples per symbol
PS_SAMPLES	= 50	// Samples of the pulse shaping
)
(
`ifdef USE_POWER_PINS
    inout vdd,	// User area 1 1.8V supply
    inout vss,	// User area 1 digital ground
`endif
input 									CLK 	,  	// Clock
input 									RST	,		// Reset low active	
input 									EN		,		// Enable
input									   BitIn	,		// Incoming Bitstream
output signed [(DW_IN-I_SEL):I_SEL-1] I,		// In-phase component
output signed [(DW_IN-I_SEL):I_SEL-1]	Q,		// Quadrature component
output [5:0] addI,
output [5:0] addQ,
output  [37:0] io_oeb 
);

	assign io_oeb   [6:0]  = {12{1'b1}};
	assign io_oeb   [37:7]  = {12{1'b0}};

	wire   									En_1M;
	wire   									En_1M_dly;
	wire   									En_2M;
	wire   				 					wi_b2r;
	wire  [SAMPLES-1:0] 				wi_Reg2Rom;
	wire 										wi_Reg2Rom_delay;
	wire 	[I_SEL-2:-(DW_IN-I_SEL)] 	I_ROM;
	wire 	[I_SEL-1:-(DW_IN-I_SEL)] 	I_Cmplted;
	wire 	[I_SEL-2:-(DW_IN-I_SEL)] 	Q_ROM;
	wire 	[I_SEL-1:-(DW_IN-I_SEL)] 	Q_Cmplted;
	wire 	[$clog2(PS_SAMPLES)-1:0] 		addressI;
	wire 	[$clog2(PS_SAMPLES)-1:0] 		addressQ;



	// This module converts from bitstream to symbosl for OQPSK
	buffer_TX 	#(SAMPLES-1'b1)  	 		bit2symb
	(
		.CLK50M		( 	CLK 	),	// clock 50MHz
		.RST			(	RST  	),	// Reset, low active
		.EN			( 	En_2M 	),	// Enable 2 MHz
		.BitIn		( 	BitIn 	),	// Incoming bitstream
		.regi 		( 	wi_b2r	)		// buffer of 2 bits.
	);

	// Register updatated each 1MHz
	REG_TX 		#(SAMPLES, SAMPLES) 	Register
	(
		.CLK 		( 	CLK 	), 	// Clock 50MHz
		.RST 		( 	RST 	),		// Reset, low active
		.EN 		( 	En_1M	),		// Enable 1 MHz
		.In		( {BitIn,wi_b2r}),
		.Out 		( 	wi_Reg2Rom	)
	);

	assign Sym = wi_Reg2Rom;

	// Register updatated each 1MHz and it's delayed 1/2 symbol time
	REG_TX 		#(1, 1) 				Reg_Delay_Q
	(
		.CLK 		( 	CLK 	), 	// Clock 50MHz
		.RST 		( 	RST 	),		// Reset, low active
		.EN 		( 	En_1M_dly	),	// Enable 1 MHz delayed
		.In		( 	wi_Reg2Rom[1]		),
		.Out 		( 	wi_Reg2Rom_delay	)
	); 

	// **** CONTROL OF THE ROM MEMORY ****
	ctrl_2ROMS									// ROM memory module
	#(
		.SAMPLES 	( 	PS_SAMPLES 	)
	)
	ROM_ctrl_mdl
	(
		.CLK_50M ( 	CLK	),		// Clock input at 50MHz
		.rst 		( 	RST	),		// Reset low active
		.EN1 		( 	EN		), 	// Enable of the first counter.
		.addr1 	( 	addressI	),	// Address of the rom memory
		.addr2 	( 	addressQ	),	// Address of the rom memory
		.F50 		(	En_1M 	),	// Enable of 2MHz
		.F25 		(	En_1M_dly	),	// 
		.F2M		( 	En_2M	)	
	);

	assign C_F50 = En_1M;
	assign C_F25 = En_1M_dly;
	assign C_F2M = En_2M;
	assign addI = addressI;
	assign addQ = addressQ;

	// **** RCOSINE PULSE SHAPING ****
	pulse_shaping_v1 #(.SAMPLES(PS_SAMPLES), .DW(DW_IN), .I(I_SEL-1)) p_shaping_I(
		.reset(RST),
		.counter_addr(addressI),
		.bit_in(wi_Reg2Rom[0]),
		.out_filtered_s(I)
	);

	pulse_shaping_v1 #(.SAMPLES(PS_SAMPLES), .DW(DW_IN), .I(I_SEL-1)) p_shaping_Q(
		.reset(RST),
		.counter_addr(addressQ),
		.bit_in(wi_Reg2Rom_delay),
//		.bit_in(wi_Reg2Rom[1]),		
		.out_filtered_s(Q)
	);	
//		`include "MathFun.vh"

endmodule

module buffer_TX
#(parameter SAMPLES=1)
(
input 					CLK50M 		,
input 					RST			,
input 					EN			,
input 					BitIn		,
output reg [SAMPLES-1:0] 	regi
);

//integer ii;
always@(posedge CLK50M or negedge RST)
begin
if (!RST)
	begin
			regi<={SAMPLES{1'b0}};
	end
else
	if(EN)
	begin
		regi 	<= BitIn;
	end
end

endmodule


module  ctrl_2ROMS									// ROM memory module
#(parameter SAMPLES=50)
(
input 							CLK_50M 	,	// Clock input at 50MHz
input 							rst			,	// Reset low active
input 							EN1 		,	// Enable of the first counter.
output 	[$clog2(SAMPLES)-1:0] 	addr1 		, 	// Address of the rom memory I component
output 	[$clog2(SAMPLES)-1:0] 	addr2 		, 	// Address of the rom memory Q component
output	 						F50 		,	// 1M enable each 50 clocks
output	 						F25 		,	// 1M enable each 25 clocks
output 							F2M				// Signal at 2 Megahertz
);


reg 	[$clog2(SAMPLES)-1:0] 	Counter1;
reg 	[$clog2(SAMPLES)-1:0] 	Counter2;
always@(posedge CLK_50M or negedge rst)
if(!rst)
	Counter1 <=0;
else 
	if(EN1)
	begin
		if (F50)
			Counter1  	<= 0;
		else 
			Counter1 	<= Counter1 + 1'b1;
	end

always@(posedge CLK_50M or negedge rst)
if(!rst)
	Counter2 <=0;
else 
	if(EN1)
	begin
		if (F25)
			Counter2  	<= 0;
		else 
			Counter2 	<= Counter2 + 1'b1;
	end
	
assign F50 		= (Counter1==6'd49)? 1'b1:1'b0;
assign F25 		= (Counter1==6'd24)? 1'b1:1'b0;
assign F2M 		= (F50|F25);
// assign addr1 	= Counter1[log2(SAMPLES):1];
//assign addr2 	= Counter2[log2(SAMPLES):1]; 
assign addr1 	= Counter1;
assign addr2 	= Counter2;

//	`include "MathFun.vh"
endmodule




module pulse_shaping_v1 #(parameter SAMPLES=50, DW=13, I=0)
(	input reset,
	input [$clog2(SAMPLES)-1:0] counter_addr,
	input bit_in,
	output signed [I-1:-(DW-I)] out_filtered_s
);

// `include "MathFun.vh"

wire signed[I-1:-(DW-I)] o_rom_1, o_rom_2, o_rom_3;
reg signed[I-1:-(DW-I)] o_rom_1_1, o_rom_2_1, o_rom_3_1;
reg bit_in_0;
reg bit_in_1;
reg bit_in_2;
reg ctl;
reg ctl_1;
reg [1:0] counter = 2'b00;

	always @(*) begin
		if (!reset) begin
			ctl = 1'b0;
			ctl_1 = bit_in;
			bit_in_0 = 1'b0;
		end
		else
			bit_in_0 = bit_in;
			if (counter_addr == 6'd49) begin				
				ctl = 1'b1;
							
				if (bit_in_0 == ctl_1) begin
					o_rom_2_1 = (bit_in_1 == 1'b1)?o_rom_2:-o_rom_2;
					ctl_1 = bit_in_1;
				end
				else begin
					o_rom_2_1 = (bit_in_1 == 1'b1)?-o_rom_2:o_rom_2;
					ctl_1 = bit_in_1;
				end
				
			end
			else begin
				ctl = 1'b0;
				o_rom_2_1 = (bit_in_1 == 1'b1)?o_rom_2:-o_rom_2;
			end
						
			
			o_rom_1_1 = (bit_in == 1'b1)?o_rom_1:-o_rom_1;			

			o_rom_3_1 = (bit_in_2 == 1'b1)?o_rom_3:-o_rom_3;
		end

  always @ (posedge ctl or negedge reset) begin
	  if(!reset) begin
				bit_in_1 <= 1'b0;
				bit_in_2 <= 1'b0;
				counter <= 2'b00;
	  end
	  else begin
		 counter <= (counter <= 2'b01)?counter + 1'b1:counter;		 
		 bit_in_1 <= bit_in;
		 bit_in_2 <= bit_in_1;
	  end
  end	

rcosine_1 #(SAMPLES,DW,I) rcos_1
(
	.addr(counter_addr),
	.out(o_rom_1) 
);

rcosine_2 #(SAMPLES,DW,I) rcos_2
(
	.addr(counter_addr),
	.out(o_rom_2) 
);

rcosine_3 #(SAMPLES,DW,I) rcos_3
(
	.addr(counter_addr),
	.out(o_rom_3) 
);


assign out_filtered_s = o_rom_1_1 + ((counter > 2'b00)?o_rom_2_1:0) + ((counter > 2'b01)?o_rom_3_1:0);
endmodule





module rcosine_1 #(parameter SAMPLES=50, DW=13, I=0)
(
input	[$clog2(SAMPLES)-1:0] addr, 
output reg signed[I-1:-(DW-I)] out
);
	always@*
	case(addr)
				00:out = 13'b0000000000000;
				01:out = 13'b0000000000000;
				02:out = 13'b0000000000010;
				03:out = 13'b0000000000100;
				04:out = 13'b0000000001000;
				05:out = 13'b0000000001100;
				06:out = 13'b0000000010010;
				07:out = 13'b0000000011000;
				08:out = 13'b0000000100000;
				09:out = 13'b0000000101000;
				10:out = 13'b0000000110000;
				11:out = 13'b0000000111001;
				12:out = 13'b0000001000001;
				13:out = 13'b0000001001001;
				14:out = 13'b0000001010000;
				15:out = 13'b0000001010111;
				16:out = 13'b0000001011011;
				17:out = 13'b0000001011101;
				18:out = 13'b0000001011110;
				19:out = 13'b0000001011011;
				20:out = 13'b0000001010101;
				21:out = 13'b0000001001100;
				22:out = 13'b0000000111111;
				23:out = 13'b0000000101110;
				24:out = 13'b0000000011001;
				25:out = 13'b0000000000000;
				26:out = -13'b0000000011101;
				27:out = -13'b0000000111101;
				28:out = -13'b0000001100001;
				29:out = -13'b0000010001001;
				30:out = -13'b0000010110010;
				31:out = -13'b0000011011101;
				32:out = -13'b0000100001010;
				33:out = -13'b0000100110110;
				34:out = -13'b0000101100010;
				35:out = -13'b0000110001100;
				36:out = -13'b0000110110011;
				37:out = -13'b0000111010101;
				38:out = -13'b0000111110010;
				39:out = -13'b0001000001000;
				40:out = -13'b0001000010110;
				41:out = -13'b0001000011011;
				42:out = -13'b0001000010101;
				43:out = -13'b0001000000100;
				44:out = -13'b0000111100110;
				45:out = -13'b0000110111010;
				46:out = -13'b0000110000000;
				47:out = -13'b0000100110111;
				48:out = -13'b0000011011111;
				49:out = -13'b0000001110111;
	default: out = 13'b0000000000000;
	endcase
//			`include "MathFun.vh"
endmodule
		





module rcosine_2 #(parameter SAMPLES=50, DW=13, I=0)
(
input	[$clog2(SAMPLES)-1:0] addr, 
output reg signed[I-1:-(DW-I)] out
);
	always@*
	case(addr)
			00:out = 13'b0000000000000;
			01:out = 13'b0000010000110;
			02:out = 13'b0000100011011;
			03:out = 13'b0000110111110;
			04:out = 13'b0001001101110;
			05:out = 13'b0001100101010;
			06:out = 13'b0001111110000;
			07:out = 13'b0010010111111;
			08:out = 13'b0010110010101;
			09:out = 13'b0011001110000;
			10:out = 13'b0011101001110;
			11:out = 13'b0100000101101;
			12:out = 13'b0100100001001;
			13:out = 13'b0100111100010;
			14:out = 13'b0101010110100;
			15:out = 13'b0101101111110;
			16:out = 13'b0110000111100;
			17:out = 13'b0110011101101;
			18:out = 13'b0110110001111;
			19:out = 13'b0111000011111;
			20:out = 13'b0111010011100;
			21:out = 13'b0111100000101;
			22:out = 13'b0111101011000;
			23:out = 13'b0111110010100;
			24:out = 13'b0111110111000;
			25:out = 13'b0111111000100;
			26:out = 13'b0111110111000;
			27:out = 13'b0111110010100;
			28:out = 13'b0111101011000;
			29:out = 13'b0111100000101;
			30:out = 13'b0111010011100;
			31:out = 13'b0111000011111;
			32:out = 13'b0110110001111;
			33:out = 13'b0110011101101;
			34:out = 13'b0110000111100;
			35:out = 13'b0101101111110;
			36:out = 13'b0101010110100;
			37:out = 13'b0100111100010;
			38:out = 13'b0100100001001;
			39:out = 13'b0100000101101;
			40:out = 13'b0011101001110;
			41:out = 13'b0011001110000;
			42:out = 13'b0010110010101;
			43:out = 13'b0010010111111;
			44:out = 13'b0001111110000;
			45:out = 13'b0001100101010;
			46:out = 13'b0001001101110;
			47:out = 13'b0000110111110;
			48:out = 13'b0000100011011;
			49:out = 13'b0000010000110;
	default: out = 13'b0000000000000;
	endcase
//			`include "MathFun.vh"
endmodule
		





module rcosine_3 #(parameter SAMPLES=50, DW=13, I=0)
(
input	[$clog2(SAMPLES)-1:0] addr, 
output reg signed[I-1:-(DW-I)] out
);
	always@*
	case(addr)
			00:out = -13'b0000000000000;
			01:out = -13'b0000001110111;
			02:out = -13'b0000011011111;
			03:out = -13'b0000100110111;
			04:out = -13'b0000110000000;
			05:out = -13'b0000110111010;
			06:out = -13'b0000111100110;
			07:out = -13'b0001000000100;
			08:out = -13'b0001000010101;
			09:out = -13'b0001000011011;
			10:out = -13'b0001000010110;
			11:out = -13'b0001000001000;
			12:out = -13'b0000111110010;
			13:out = -13'b0000111010101;
			14:out = -13'b0000110110011;
			15:out = -13'b0000110001100;
			16:out = -13'b0000101100010;
			17:out = -13'b0000100110110;
			18:out = -13'b0000100001010;
			19:out = -13'b0000011011101;
			20:out = -13'b0000010110010;
			21:out = -13'b0000010001001;
			22:out = -13'b0000001100001;
			23:out = -13'b0000000111101;
			24:out = -13'b0000000011101;
			25:out = 13'b0000000000000;
			26:out = 13'b0000000011001;
			27:out = 13'b0000000101110;
			28:out = 13'b0000000111111;
			29:out = 13'b0000001001100;
			30:out = 13'b0000001010101;
			31:out = 13'b0000001011011;
			32:out = 13'b0000001011110;
			33:out = 13'b0000001011101;
			34:out = 13'b0000001011011;
			35:out = 13'b0000001010111;
			36:out = 13'b0000001010000;
			37:out = 13'b0000001001001;
			38:out = 13'b0000001000001;
			39:out = 13'b0000000111001;
			40:out = 13'b0000000110000;
			41:out = 13'b0000000101000;
			42:out = 13'b0000000100000;
			43:out = 13'b0000000011000;
			44:out = 13'b0000000010010;
			45:out = 13'b0000000001100;
			46:out = 13'b0000000001000;
			47:out = 13'b0000000000100;
			48:out = 13'b0000000000010;
			49:out = 13'b0000000000000;
		default: out = 13'b0000000000000;
	endcase
//			`include "MathFun.vh"
endmodule
		
		
		
		
		
module REG_TX
#(parameter DW_IN=2, I_SEL=2)
(
input 													CLK, 			
input 													RST,
input 													EN,
input 			signed	[I_SEL-1:-(DW_IN-I_SEL)] 		In,
output reg		signed	[I_SEL-1:-(DW_IN-I_SEL)]		Out
);

always@(posedge CLK or negedge RST)
if (!RST)
	begin
		Out 		<= {DW_IN{1'b0}};
	end
else
	begin
		if(EN==1'b1)
			begin							
				Out 		<= In;
			end
	end
	endmodule

