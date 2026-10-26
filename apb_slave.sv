`timescale 1ns/1ns

//////////////////////////////////////////////////////////////////////////////
// APB slave for the 8x8 FP8 matmul. 16-bit registers, one register per
// signal, word-indexed (PADDR = register number).
//
//   PADDR  Name      Access  Bits   Meaning
//   0x0    CTRL      W       [0]    write 1 -> start the matmul (self-clearing)
//   0x1    ADDR_A    W       [9:0]  address_mat_a
//   0x2    ADDR_B    W       [9:0]  address_mat_b
//   0x3    ADDR_C    W       [9:0]  address_mat_c
//   0x4    STRIDE_A  W       [7:0]  address_stride_a
//   0x5    STRIDE_B  W       [7:0]  address_stride_b
//   0x6    STRIDE_C  W       [7:0]  address_stride_c
//   0x7    DONE      R       [0]    matmul finished (held until next start)
//   0x8    FLAGS     R       [0]    an FP8 exception happened (held until next start)
//
// Config registers are written only, DONE/FLAGS are read only. Any other read
// returns 0.
//////////////////////////////////////////////////////////////////////////////
module apb_slave (
  input  logic        PCLK,
  input  logic        PRESETn,
  input  logic [3:0]  PADDR,
  input  logic        PWRITE,
  input  logic        PSEL,
  input  logic        PENABLE,
  input  logic [15:0] PWDATA,
  output logic [15:0] PRDATA,
  output logic        PREADY,

  // to the matmul
  output logic        start,              // one-cycle pulse
  output logic [9:0]  address_mat_a,
  output logic [9:0]  address_mat_b,
  output logic [9:0]  address_mat_c,
  output logic [7:0]  address_stride_a,
  output logic [7:0]  address_stride_b,
  output logic [7:0]  address_stride_c,

  // from the matmul
  input  logic        done,               // one-cycle pulse from the core
  input  logic        flags               // brief level, only high while an
                                          // offending FP op is in flight
);

  localparam logic [3:0] REG_CTRL     = 4'h0,
                         REG_ADDR_A   = 4'h1,
                         REG_ADDR_B   = 4'h2,
                         REG_ADDR_C   = 4'h3,
                         REG_STRIDE_A = 4'h4,
                         REG_STRIDE_B = 4'h5,
                         REG_STRIDE_C = 4'h6,
                         REG_DONE     = 4'h7,
                         REG_FLAGS    = 4'h8;

  // Always ready: every transfer is SETUP + ACCESS, no wait states.
  assign PREADY = 1'b1;

  // A transfer takes effect on the clock edge where PSEL and PENABLE are
  // both high (the ACCESS phase), so no separate state machine is needed.
  logic wr_en;
  assign wr_en = PSEL & PENABLE & PWRITE;

  // done and flags are too short to be caught by a polling read, so they are
  // held in sticky bits that the next start clears.
  logic done_q, flags_q;

  always_ff @(posedge PCLK) begin
    if (!PRESETn) begin
      start            <= 1'b0;
      address_mat_a    <= '0;
      address_mat_b    <= '0;
      address_mat_c    <= '0;
      address_stride_a <= '0;
      address_stride_b <= '0;
      address_stride_c <= '0;
      done_q           <= 1'b0;
      flags_q          <= 1'b0;
    end else begin
      start <= 1'b0;

      if (done)  done_q  <= 1'b1;
      if (flags) flags_q <= 1'b1;

      if (wr_en) begin
        case (PADDR)
          REG_CTRL: begin
            start <= PWDATA[0];
            if (PWDATA[0]) begin
              done_q  <= 1'b0;
              flags_q <= 1'b0;
            end
          end
          REG_ADDR_A:   address_mat_a    <= PWDATA[9:0];
          REG_ADDR_B:   address_mat_b    <= PWDATA[9:0];
          REG_ADDR_C:   address_mat_c    <= PWDATA[9:0];
          REG_STRIDE_A: address_stride_a <= PWDATA[7:0];
          REG_STRIDE_B: address_stride_b <= PWDATA[7:0];
          REG_STRIDE_C: address_stride_c <= PWDATA[7:0];
          default: ;
        endcase
      end
    end
  end

  // Read mux on PADDR only, so PRDATA is valid for the whole access phase.
  always_comb begin
    case (PADDR)
      REG_DONE:  PRDATA = {15'b0, done_q};
      REG_FLAGS: PRDATA = {15'b0, flags_q};
      default:   PRDATA = 16'h0000;
    endcase
  end

endmodule
