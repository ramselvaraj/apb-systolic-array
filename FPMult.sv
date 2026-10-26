`timescale 1ns / 1ps

module FPMult(
		a,
		b,
		result,
		flags
    );

	localparam EXP_W = 3 ;				// Exponent bits
	localparam MAN_W = 4 ;				// Mantissa bits (hidden bit not stored)
	localparam BIAS  = 3 ;				// 2^(EXP_W-1) - 1

	// Input Ports
	input [7:0] a;						// Input A, an 8-bit (e3m4) floating point number
	input [7:0] b;						// Input B, an 8-bit (e3m4) floating point number

	// Output ports
	output [7:0] result ;				// Product, 8-bit (e3m4) floating point number
	output [4:0] flags ;				// Exception flags

	//////////////////////////////////////////////////////////////////////////
	// Prep stage (was FPMult_PrepModule): split operands, flag exceptions,
	// mantissa product
	//////////////////////////////////////////////////////////////////////////
	logic Sa ;							// A's sign
	logic Sb ;							// B's sign
	logic Sp ;							// Product sign

	logic [EXP_W-1:0] Ea ;				// A's exponent
	logic [EXP_W-1:0] Eb ;				// B's exponent

	logic [MAN_W-1:0] Ma ;				// A's mantissa
	logic [MAN_W-1:0] Mb ;				// B's mantissa

	logic ANaN ;						// A is a NaN
	logic BNaN ;						// B is a NaN

	logic AInf ;						// A is infinity
	logic BInf ;						// B is infinity

	logic AZero ;						// A is zero (exponent 0)
	logic BZero ;						// B is zero (exponent 0)

	logic [2*MAN_W+1:0] Mp ;			// Mantissa product, (1.Ma)*(1.Mb), 10 bits

	assign Sa = a[7] ;
	assign Sb = b[7] ;
	assign Ea = a[6:4] ;
	assign Eb = b[6:4] ;
	assign Ma = a[3:0] ;
	assign Mb = b[3:0] ;

	assign ANaN  = &Ea & |Ma ;			// All one exponent and non-zero mantissa
	assign BNaN  = &Eb & |Mb ;
	assign AInf  = &Ea & ~|Ma ;			// All one exponent and zero mantissa
	assign BInf  = &Eb & ~|Mb ;
	assign AZero = ~|Ea ;
	assign BZero = ~|Eb ;

	assign Sp = Sa ^ Sb ;				// Equal signs give a positive product
	assign Mp = {1'b1, Ma} * {1'b1, Mb} ;

	//////////////////////////////////////////////////////////////////////////
	// Execute stage (was FPMult_ExecuteModule): normalize product, add exponents
	//////////////////////////////////////////////////////////////////////////
	logic Ovf ;							// Product >= 2.0, needs one right shift
	logic [MAN_W-1:0] NormM ;			// Normalized mantissa
	logic G ;							// Guard bit
	logic S ;							// Sticky bit
	logic [4:0] NormE ;					// Normalized exponent (two's complement, can be <= 0)

	assign Ovf   = Mp[9] ;
	assign NormM = Ovf ? Mp[8:5] : Mp[7:4] ;
	assign G     = Ovf ? Mp[4]   : Mp[3] ;
	assign S     = Ovf ? |Mp[3:0] : |Mp[2:0] ;
	assign NormE = {2'b00, Ea} + {2'b00, Eb} + {4'b0000, Ovf} - BIAS ;

	//////////////////////////////////////////////////////////////////////////
	// Round stage (was FPMult_RoundModule): round to nearest even
	//////////////////////////////////////////////////////////////////////////
	logic RoundUp ;
	logic [MAN_W:0] RoundSum ;			// Rounded mantissa with room for carry
	logic [MAN_W-1:0] RoundM ;
	logic [4:0] FinalE ;				// Exponent after rounding

	assign RoundUp  = G & (S | NormM[0]) ;
	assign RoundSum = {1'b0, NormM} + RoundUp ;
	assign RoundM   = RoundSum[MAN_W-1:0] ;
	assign FinalE   = NormE + RoundSum[MAN_W] ;		// Mantissa carry bumps the exponent

	//////////////////////////////////////////////////////////////////////////
	// Exception stage: special values, overflow, underflow, flags
	//////////////////////////////////////////////////////////////////////////
	logic NaNOut ;
	logic InfOut ;
	logic ZeroOut ;
	logic OvfOut ;
	logic Underflow ;

	assign NaNOut = ANaN | BNaN | (AInf & BZero) | (BInf & AZero) ;		// inf*0 is invalid
	assign InfOut = ~NaNOut & (AInf | BInf) ;
	assign ZeroOut = ~NaNOut & ~InfOut & (AZero | BZero | NormE[4] | ~|NormE) ;
	assign OvfOut = ~NaNOut & ~InfOut & ~ZeroOut & (FinalE[3] | &FinalE[2:0]) ;	// exponent >= 7
	assign Underflow = ZeroOut & ~AZero & ~BZero ;

	assign result = NaNOut ? 8'h78 :
	                InfOut ? {Sp, 7'b1110000} :
	                ZeroOut ? {Sp, 7'b0000000} :
	                OvfOut ? {Sp, 7'b1110000} :
	                {Sp, FinalE[2:0], RoundM} ;

	assign flags = {OvfOut,													// Overflow
	                Underflow,													// Underflow
	                1'b0,														// DivideByZero (not used)
	                ANaN | BNaN | (AInf & BZero) | (BInf & AZero),				// Invalid
	                (~NaNOut & ~InfOut & ~AZero & ~BZero & (G | S)) | OvfOut | Underflow} ;		// Inexact

endmodule
