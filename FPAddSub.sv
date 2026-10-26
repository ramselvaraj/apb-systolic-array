`timescale 1ns / 1ps

module FPAddSub(
		a,
		b,
		operation,
		result,
		flags
	);

	localparam EXP_W = 3 ;				// Exponent bits
	localparam MAN_W = 4 ;				// Mantissa bits (hidden bit not stored)
	localparam BIAS  = 3 ;				// 2^(EXP_W-1) - 1

	input [7:0] a ;						// Input A, an 8-bit (e3m4) floating point number
	input [7:0] b ;						// Input B, an 8-bit (e3m4) floating point number
	input operation ;					// Operation select signal (0/Add, 1/Sub)

	output [7:0] result ;				// Result of the operation
	output [4:0] flags ;				// Exception flags

	//////////////////////////////////////////////////////////////////////////
	// Prealign stage (was FPAddSub_PrealignModule)
	//////////////////////////////////////////////////////////////////////////
	logic Sa_0 ;						// A's sign
	logic Sb_0 ;						// B's effective sign (flipped when subtracting)
	logic ANaN ;						// A is a NaN
	logic BNaN ;						// B is a NaN
	logic AInf ;						// A is infinity
	logic BInf ;						// B is infinity
	logic AZero ;						// A is zero (exponent 0)
	logic BZero ;						// B is zero (exponent 0)
	logic [6:0] Aout_0 ;				// A without sign (zero if exponent is 0)
	logic [6:0] Bout_0 ;				// B without sign (zero if exponent is 0)

	assign Sa_0 = a[7] ;
	assign Sb_0 = b[7] ^ operation ;

	assign ANaN  = &a[6:4] & |a[3:0] ;
	assign BNaN  = &b[6:4] & |b[3:0] ;
	assign AInf  = &a[6:4] & ~|a[3:0] ;
	assign BInf  = &b[6:4] & ~|b[3:0] ;
	assign AZero = ~|a[6:4] ;
	assign BZero = ~|b[6:4] ;

	assign Aout_0 = AZero ? 7'b0000000 : a[6:0] ;
	assign Bout_0 = BZero ? 7'b0000000 : b[6:0] ;

	//////////////////////////////////////////////////////////////////////////
	// Align stage (was FPAddSub_AlignModule + AlignShift1/2)
	// Pick the larger magnitude, shift the smaller mantissa right by the
	// exponent difference, keeping guard/round/sticky bits.
	//////////////////////////////////////////////////////////////////////////
	logic MaxAB_1 ;						// Indicates the larger of A and B (0/A, 1/B)
	logic [6:0] Lg_1 ;					// Larger operand (no sign)
	logic [6:0] Sm_1 ;					// Smaller operand (no sign)
	logic [EXP_W-1:0] CExp_1 ;			// Common (larger) exponent
	logic [EXP_W-1:0] Shift_1 ;			// Number of steps to shift smaller mantissa right
	logic [MAN_W:0] Mmax_1 ;			// Larger mantissa with hidden bit
	logic [MAN_W:0] MminS_1 ;			// Smaller mantissa with hidden bit
	logic [15:0] al_wide ;				// Smaller mantissa after shift, lost bits kept in [7:0]
	logic [MAN_W+3:0] Mmin_3 ;			// Aligned smaller mantissa: 5 bits + G, R, S

	assign MaxAB_1 = (Aout_0 < Bout_0) ;
	assign Lg_1 = MaxAB_1 ? Bout_0 : Aout_0 ;
	assign Sm_1 = MaxAB_1 ? Aout_0 : Bout_0 ;
	assign CExp_1 = Lg_1[6:4] ;
	assign Shift_1 = Lg_1[6:4] - Sm_1[6:4] ;
	assign Mmax_1  = {|Lg_1[6:4], Lg_1[3:0]} ;
	assign MminS_1 = {|Sm_1[6:4], Sm_1[3:0]} ;

	assign al_wide = {MminS_1, 3'b000, 8'h00} >> Shift_1 ;
	assign Mmin_3  = {al_wide[15:9], al_wide[8] | (|al_wide[7:0])} ;		// Sticky ORed into last bit

	//////////////////////////////////////////////////////////////////////////
	// Execution stage (was FPAddSub_ExecutionModule): add / subtract
	//////////////////////////////////////////////////////////////////////////
	logic Opr_4 ;						// Effective operation (0/add, 1/subtract magnitudes)
	logic PSgn_4 ;						// Sign of the larger operand
	logic [MAN_W+4:0] Sum_4 ;			// 1 carry bit + 5 mantissa bits + G, R, S

	assign Opr_4 = Sa_0 ^ Sb_0 ;
	assign PSgn_4 = MaxAB_1 ? Sb_0 : Sa_0 ;
	assign Sum_4 = Opr_4 ? ({1'b0, Mmax_1, 3'b000} - {1'b0, Mmin_3}) : ({1'b0, Mmax_1, 3'b000} + {1'b0, Mmin_3}) ;

	//////////////////////////////////////////////////////////////////////////
	// Normalize stage (was FPAddSub_NormalizeModule + NormalizeShift1/2)
	// Count leading zeros, shift left, adjust exponent, split off G/R/S.
	//////////////////////////////////////////////////////////////////////////
	logic [3:0] Shift_5 ;				// Number of steps to shift sum left
	logic [MAN_W+4:0] SumS_7 ;			// Normalized sum
	logic [MAN_W-1:0] NormM_8 ;			// Normalized mantissa
	logic [4:0] NormE_8 ;				// Adjusted exponent (two's complement, can be <= 0)
	logic ZeroSum_8 ;					// Zero flag
	logic NegE_8 ;						// Exponent <= 0 (underflow)
	logic FG_8 ;						// Guard bit
	logic R_8 ;							// Round bit
	logic S_8 ;							// Sticky bit

	assign Shift_5 = (
		Sum_4[8] ? 4'd0 :
		Sum_4[7] ? 4'd1 :
		Sum_4[6] ? 4'd2 :
		Sum_4[5] ? 4'd3 :
		Sum_4[4] ? 4'd4 :
		Sum_4[3] ? 4'd5 :
		Sum_4[2] ? 4'd6 :
		Sum_4[1] ? 4'd7 :
		Sum_4[0] ? 4'd8 : 4'd9
	);

	assign SumS_7 = Sum_4 << Shift_5 ;

	assign ZeroSum_8 = ~|Sum_4 ;
	assign NormE_8 = {2'b00, CExp_1} + 5'd1 - {1'b0, Shift_5} ;
	assign NegE_8 = NormE_8[4] | ~|NormE_8 ;
	assign NormM_8 = SumS_7[7:4] ;
	assign FG_8 = SumS_7[3] ;
	assign R_8  = SumS_7[2] ;
	assign S_8  = |SumS_7[1:0] ;

	//////////////////////////////////////////////////////////////////////////
	// Round stage (was FPAddSub_RoundModule): round to nearest even
	//////////////////////////////////////////////////////////////////////////
	logic RoundUp ;
	logic [MAN_W:0] RoundSum ;			// Rounded mantissa with room for carry
	logic [MAN_W-1:0] RoundM ;
	logic [4:0] FinalE ;				// Exponent after rounding

	assign RoundUp  = FG_8 & (R_8 | S_8 | NormM_8[0]) ;
	assign RoundSum = {1'b0, NormM_8} + RoundUp ;
	assign RoundM   = RoundSum[MAN_W-1:0] ;
	assign FinalE   = NormE_8 + RoundSum[MAN_W] ;

	//////////////////////////////////////////////////////////////////////////
	// Exception stage (was FPAddSub_ExceptionModule): special values and flags
	//////////////////////////////////////////////////////////////////////////
	logic InvalidOp ;
	logic NaNOut ;
	logic InfOut ;
	logic ZeroOut ;
	logic OvfOut ;
	logic Underflow ;
	logic ZeroSgn ;

	assign InvalidOp = ANaN | BNaN | (AInf & BInf & (Sa_0 ^ Sb_0)) ;			// NaN input or inf - inf
	assign NaNOut = InvalidOp ;
	assign InfOut = ~NaNOut & (AInf | BInf) ;
	assign ZeroOut = ~NaNOut & ~InfOut & (ZeroSum_8 | NegE_8) ;
	assign OvfOut = ~NaNOut & ~InfOut & ~ZeroOut & (FinalE[3] | &FinalE[2:0]) ;	// exponent >= 7
	assign Underflow = ZeroOut & ~ZeroSum_8 ;
	assign ZeroSgn = ZeroSum_8 ? (Sa_0 & Sb_0) : PSgn_4 ;

	assign result = NaNOut ? 8'h78 :
	                InfOut ? {(AInf ? Sa_0 : Sb_0), 7'b1110000} :
	                ZeroOut ? {ZeroSgn, 7'b0000000} :
	                OvfOut ? {PSgn_4, 7'b1110000} :
	                {PSgn_4, FinalE[2:0], RoundM} ;

	assign flags = {OvfOut,													// Overflow
	                Underflow,													// Underflow
	                1'b0,														// DivideByZero (not used)
	                InvalidOp,													// Invalid
	                (~NaNOut & ~InfOut & (FG_8 | R_8 | S_8)) | OvfOut | Underflow} ;	// Inexact

endmodule
