`timescale 1ns/1ns
`define DWIDTH 8
`define AWIDTH 10
`define MEM_SIZE 1024

`define MAT_MUL_SIZE 4
`define MASK_WIDTH 4
`define LOG2_MAT_MUL_SIZE 2

`define BB_MAT_MUL_SIZE `MAT_MUL_SIZE
`define NUM_CYCLES_IN_MAC 3
`define MEM_ACCESS_LATENCY 1
`define REG_DATAWIDTH 32
`define REG_ADDRWIDTH 8
`define ADDR_STRIDE_WIDTH 8
`define MAX_BITS_POOL 3

//////////////////////////////////////////////////////////////////////////////
// Design with memories, 8x8 version.
//
// Each matrix is stored in TWO 32-bit RAM blocks that share one address:
//   RAM *0 = low  32 bits = 4 FP8 values for rows/cols 0-3 (top / left half)
//   RAM *1 = high 32 bits = 4 FP8 values for rows/cols 4-7 (bottom / right half)
// So one address holds one 64-bit word = 8 FP8 values:
//   A word k : byte i = A[i][k]      B word k : byte j = B[k][j]
//   C word j : byte i = C[i][j]
//
// External ports are 64 bits wide: bits [31:0] go to RAM *0, bits [63:32] go to
// RAM *1. One external write (we_ext != 0) writes both halves at the same address.
//////////////////////////////////////////////////////////////////////////////
module matrix_multiplication(
  PCLK,
  PRESETn,
  pe_resetn,
  PADDR,
  PWRITE,
  PSEL,
  PENABLE,
  PWDATA,
  PRDATA,
  PREADY,
  bram_addr_a_ext,
  bram_rdata_a_ext,
  bram_wdata_a_ext,
  bram_we_a_ext,
  bram_addr_b_ext,
  bram_rdata_b_ext,
  bram_wdata_b_ext,
  bram_we_b_ext,
  bram_addr_c_ext,
  bram_rdata_c_ext,
  bram_wdata_c_ext,
  bram_we_c_ext
);

  // APB slave interface: replaces the old start/done/address/stride pins
  input         PCLK;
  input         PRESETn;
  input         pe_resetn;
  input  [3:0]  PADDR;
  input         PWRITE;
  input         PSEL;
  input         PENABLE;
  input  [15:0] PWDATA;
  output [15:0] PRDATA;
  output        PREADY;

  // internal names for the clock and reset (declared before first use)
  wire clk    = PCLK;
  wire resetn = PRESETn;
  input  [`AWIDTH-1:0] bram_addr_a_ext;
  output [2*`MAT_MUL_SIZE*`DWIDTH-1:0] bram_rdata_a_ext;
  input  [2*`MAT_MUL_SIZE*`DWIDTH-1:0] bram_wdata_a_ext;
  input  [`MASK_WIDTH-1:0] bram_we_a_ext;
  input  [`AWIDTH-1:0] bram_addr_b_ext;
  output [2*`MAT_MUL_SIZE*`DWIDTH-1:0] bram_rdata_b_ext;
  input  [2*`MAT_MUL_SIZE*`DWIDTH-1:0] bram_wdata_b_ext;
  input  [`MASK_WIDTH-1:0] bram_we_b_ext;
  input  [`AWIDTH-1:0] bram_addr_c_ext;
  output [2*`MAT_MUL_SIZE*`DWIDTH-1:0] bram_rdata_c_ext;
  input  [2*`MAT_MUL_SIZE*`DWIDTH-1:0] bram_wdata_c_ext;
  input  [`MASK_WIDTH-1:0] bram_we_c_ext;

  // 64-bit internal buses to the matmul; split across two 32-bit RAMs below
  wire [`AWIDTH-1:0] bram_addr_a;
  wire [2*`MAT_MUL_SIZE*`DWIDTH-1:0] bram_rdata_a;
  wire [2*`MAT_MUL_SIZE*`DWIDTH-1:0] bram_wdata_a;
  wire [`MASK_WIDTH-1:0] bram_we_a;

  wire [`AWIDTH-1:0] bram_addr_b;
  wire [2*`MAT_MUL_SIZE*`DWIDTH-1:0] bram_rdata_b;
  wire [2*`MAT_MUL_SIZE*`DWIDTH-1:0] bram_wdata_b;
  wire [`MASK_WIDTH-1:0] bram_we_b;

  wire [`AWIDTH-1:0] bram_addr_c;
  wire [2*`MAT_MUL_SIZE*`DWIDTH-1:0] bram_rdata_c;
  wire [2*`MAT_MUL_SIZE*`DWIDTH-1:0] bram_wdata_c;
  wire [`MASK_WIDTH-1:0] bram_we_c;

  // Port 0 of every RAM talks to the matmul. Port 1 is the external port.
  ////////////////////////////////////////////////////////////////
  // RAM matrix A (two blocks)
  ////////////////////////////////////////////////////////////////
  ram matrix_A0 (.addr0(bram_addr_a),
                 .d0(bram_wdata_a[31:0]),
                 .we0(bram_we_a),
                 .q0(bram_rdata_a[31:0]),
                 .addr1(bram_addr_a_ext),
                 .d1(bram_wdata_a_ext[31:0]),
                 .we1(bram_we_a_ext),
                 .q1(bram_rdata_a_ext[31:0]),
                 .clk(clk));

  ram matrix_A1 (.addr0(bram_addr_a),
                 .d0(bram_wdata_a[63:32]),
                 .we0(bram_we_a),
                 .q0(bram_rdata_a[63:32]),
                 .addr1(bram_addr_a_ext),
                 .d1(bram_wdata_a_ext[63:32]),
                 .we1(bram_we_a_ext),
                 .q1(bram_rdata_a_ext[63:32]),
                 .clk(clk));

  ////////////////////////////////////////////////////////////////
  // RAM matrix B (two blocks)
  ////////////////////////////////////////////////////////////////
  ram matrix_B0 (.addr0(bram_addr_b),
                 .d0(bram_wdata_b[31:0]),
                 .we0(bram_we_b),
                 .q0(bram_rdata_b[31:0]),
                 .addr1(bram_addr_b_ext),
                 .d1(bram_wdata_b_ext[31:0]),
                 .we1(bram_we_b_ext),
                 .q1(bram_rdata_b_ext[31:0]),
                 .clk(clk));

  ram matrix_B1 (.addr0(bram_addr_b),
                 .d0(bram_wdata_b[63:32]),
                 .we0(bram_we_b),
                 .q0(bram_rdata_b[63:32]),
                 .addr1(bram_addr_b_ext),
                 .d1(bram_wdata_b_ext[63:32]),
                 .we1(bram_we_b_ext),
                 .q1(bram_rdata_b_ext[63:32]),
                 .clk(clk));

  ////////////////////////////////////////////////////////////////
  // RAM matrix C (two blocks)
  ////////////////////////////////////////////////////////////////
  ram matrix_C0 (.addr0(bram_addr_c),
                 .d0(bram_wdata_c[31:0]),
                 .we0(bram_we_c),
                 .q0(bram_rdata_c[31:0]),
                 .addr1(bram_addr_c_ext),
                 .d1(bram_wdata_c_ext[31:0]),
                 .we1(bram_we_c_ext),
                 .q1(bram_rdata_c_ext[31:0]),
                 .clk(clk));

  ram matrix_C1 (.addr0(bram_addr_c),
                 .d0(bram_wdata_c[63:32]),
                 .we0(bram_we_c),
                 .q0(bram_rdata_c[63:32]),
                 .addr1(bram_addr_c_ext),
                 .d1(bram_wdata_c_ext[63:32]),
                 .we1(bram_we_c_ext),
                 .q1(bram_rdata_c_ext[63:32]),
                 .clk(clk));

  // Register file driven over APB
  wire        start_pulse;
  wire [`AWIDTH-1:0] address_mat_a, address_mat_b, address_mat_c;
  wire [`ADDR_STRIDE_WIDTH-1:0] address_stride_a, address_stride_b, address_stride_c;
  wire done;
  wire flags;

  apb_slave u_apb_slave (
    .PCLK(PCLK),
    .PRESETn(PRESETn),
    .PADDR(PADDR),
    .PWRITE(PWRITE),
    .PSEL(PSEL),
    .PENABLE(PENABLE),
    .PWDATA(PWDATA),
    .PRDATA(PRDATA),
    .PREADY(PREADY),
    .start(start_pulse),
    .address_mat_a(address_mat_a),
    .address_mat_b(address_mat_b),
    .address_mat_c(address_mat_c),
    .address_stride_a(address_stride_a),
    .address_stride_b(address_stride_b),
    .address_stride_c(address_stride_c),
    .done(done),
    .flags(flags)
  );

  // The matmul wants start held high until it finishes, the APB start is
  // a single pulse, so hold it here.
  reg start_mat_mul;
  wire done_mat_mul;

  always @(posedge clk)
  begin
    if (resetn == 1'b0)
      start_mat_mul <= 1'b0;
    else if (done_mat_mul)
      start_mat_mul <= 1'b0;
    else if (start_pulse)
      start_mat_mul <= 1'b1;
  end

  assign done = done_mat_mul;

  wire c_data_available;

  //Connections for bram c (output matrix)
  //bram_addr_c  -> from the matmul
  //bram_wdata_c -> from the matmul (64 bits: low half to C0, high half to C1)
  //bram_we_c    -> set to 1 when c_data is available (both C RAMs write together)
  assign bram_we_c = (c_data_available) ? 4'b1111 : 4'b0000;

  //bram a and b are only read by the matmul
  assign bram_wdata_a = 64'b0;
  assign bram_we_a    = 4'b0;
  assign bram_wdata_b = 64'b0;
  assign bram_we_b    = 4'b0;

  wire reset;
  wire pe_reset;
  assign reset    = ~resetn;
  assign pe_reset = ~pe_resetn;

  //matmul instance (8x8, built from four 4x4 blocks)
  matmul_8x8 u_matmul_8x8(
    .clk(clk),
    .reset(reset),
    .pe_reset(pe_reset),
    .start_mat_mul(start_mat_mul),
    .done_mat_mul(done_mat_mul),
    .address_mat_a(address_mat_a),
    .address_mat_b(address_mat_b),
    .address_mat_c(address_mat_c),
    .address_stride_a(address_stride_a),
    .address_stride_b(address_stride_b),
    .address_stride_c(address_stride_c),
    .a_data(bram_rdata_a),
    .a_addr(bram_addr_a),
    .b_data(bram_rdata_b),
    .b_addr(bram_addr_b),
    .c_data_out(bram_wdata_c),
    .c_addr(bram_addr_c),
    .c_data_available(c_data_available),
    .flags(flags),
    .final_mat_mul_size(8'd8)
  );

endmodule

//////////////////////////////////
//Dual port RAM (32 bits wide)
//////////////////////////////////
module ram (
    addr0,
    d0,
    we0,
    q0,
    addr1,
    d1,
    we1,
    q1,
    clk);

    input [`AWIDTH-1:0] addr0;
    input [`MASK_WIDTH*`DWIDTH-1:0] d0;
    input [`MASK_WIDTH-1:0] we0;
    output reg [`MASK_WIDTH*`DWIDTH-1:0] q0;
    input [`AWIDTH-1:0] addr1;
    input [`MASK_WIDTH*`DWIDTH-1:0] d1;
    input [`MASK_WIDTH-1:0] we1;
    output reg [`MASK_WIDTH*`DWIDTH-1:0] q1;

    input clk;

    reg [31:0] ram[((1<<`AWIDTH)-1):0];

    always @(posedge clk)
    begin
        if (|we0 == 1'b1)
        begin
            ram[addr0] <= d0;
        end
        q0 <= ram[addr0];
    end

    always @(posedge clk)
    begin
        if(|we1 == 1'b1)
        begin
            ram[addr1] <= d1;
        end
        q1 <= ram[addr1];
    end

endmodule