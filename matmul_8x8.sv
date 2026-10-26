`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 20.10.2026 13:41:50
// Design Name: 
// Module Name: matmul_8x8
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

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


module matmul_8x8( 
    input clk,
    input reset,
    input pe_reset,
    input start_mat_mul,
    output logic done_mat_mul,
    input [`AWIDTH-1:0] address_mat_a,
    input [`AWIDTH-1:0] address_mat_b,
    input [`AWIDTH-1:0] address_mat_c,
    input [`ADDR_STRIDE_WIDTH-1:0] address_stride_a,
    input [`ADDR_STRIDE_WIDTH-1:0] address_stride_b,
    input [`ADDR_STRIDE_WIDTH-1:0] address_stride_c,
    input  logic [2*`MAT_MUL_SIZE*`DWIDTH-1:0] a_data,
    output logic [`AWIDTH-1:0]                a_addr,
 
  
    input  logic [2*`MAT_MUL_SIZE*`DWIDTH-1:0] b_data,
    output logic [`AWIDTH-1:0]                b_addr,
 
    output logic [2*`MAT_MUL_SIZE*`DWIDTH-1:0] c_data_out,   // 64 bits: {bottom rows 4-7, top rows 0-3}
    output logic [`AWIDTH-1:0]                c_addr,
    output logic                              c_data_available,
 
    // OR of the FP8 exception flags of all four 4x4 blocks (64 PEs total)
    output logic                              flags,
  
    input [7:0] final_mat_mul_size      // should be 8 for 8x8.
 
);

  logic [`MAT_MUL_SIZE*`DWIDTH-1:0] a_top_data, a_bot_data, b_left_data, b_right_data;
  logic [`MAT_MUL_SIZE*`DWIDTH-1:0] a_bot_d [4];
  logic [`MAT_MUL_SIZE*`DWIDTH-1:0] b_right_d [4];
 
  always_ff @(posedge clk) begin
    a_bot_d[0]   <= a_data[2*`MAT_MUL_SIZE*`DWIDTH-1:`MAT_MUL_SIZE*`DWIDTH];
    b_right_d[0] <= b_data[2*`MAT_MUL_SIZE*`DWIDTH-1:`MAT_MUL_SIZE*`DWIDTH];
    for (int i = 1; i < 4; i++) begin
      a_bot_d[i]   <= a_bot_d[i-1];
      b_right_d[i] <= b_right_d[i-1];
    end
  end
 
  assign a_top_data  = a_data[`MAT_MUL_SIZE*`DWIDTH-1:0];
  assign b_left_data = b_data[`MAT_MUL_SIZE*`DWIDTH-1:0];
  assign a_bot_data  = a_bot_d[3];
  assign b_right_data = b_right_d[3];


  localparam ZERO = {`MAT_MUL_SIZE*`DWIDTH{1'b0}};
  
  logic [`MAT_MUL_SIZE*`DWIDTH-1:0] a_out_0, a_out_1, a_out_2, a_out_3;
  logic [`MAT_MUL_SIZE*`DWIDTH-1:0] b_out_0, b_out_1, b_out_2, b_out_3;
  logic [`MAT_MUL_SIZE*`DWIDTH-1:0] c_out_0, c_out_1, c_out_2, c_out_3;
 
 
  logic done_0, done_1, done_2, done_3;
  logic flags_0, flags_1, flags_2, flags_3;   // per-block exception flags
  logic  cv_0,cv_1,cv_2 ,cv_3;
  logic [`AWIDTH-1:0] aa_0, aa_1, aa_2, aa_3;
  logic [`AWIDTH-1:0] ba_0, ba_1, ba_2, ba_3;
  logic [`AWIDTH-1:0] ca_0, ca_1, ca_2, ca_3;






  // four instantiation of matmul_4x4 
  // top left block
  
  matmul_4x4_systolic dut00 (
    .clk(clk), 
    .reset(reset), 
    .pe_reset(pe_reset),
    .start_mat_mul(start_mat_mul), 
    .done_mat_mul(done_0),
    .address_mat_a(address_mat_a), 
    .address_mat_b(address_mat_b), 
    .address_mat_c(address_mat_c),
    .address_stride_a(address_stride_a), 
    .address_stride_b(address_stride_b), 
    .address_stride_c(address_stride_c),
    .a_data(a_top_data),
     .b_data(b_left_data),
    .a_data_in(ZERO),  
    .b_data_in(ZERO),
    .c_data_in(ZERO),   
    .c_data_out(c_out_0),
    .a_data_out(a_out_0),  
    .b_data_out(b_out_0),
    .a_addr(aa_0), 
    .b_addr(ba_0), 
    .c_addr(ca_0),
    .c_data_available(cv_0),
    .validity_mask_a_rows(4'b1111), 
    .validity_mask_a_cols_b_rows(4'b1111), 
    .validity_mask_b_cols(4'b1111),
    .final_mat_mul_size(8'd8), 
     .a_loc(8'd0),                       // check this once i gave them now based on the design but i think the design is opposite to what they wanted to do. should be revere a value inplace of b and b onplace of a for these signals.
    .b_loc(8'd0),
    .flags(flags_0)
  );
 

    // top right block
    
  matmul_4x4_systolic dut01 (
    .clk(clk), 
    .reset(reset), 
    .pe_reset(pe_reset),
    .start_mat_mul(start_mat_mul), 
    .done_mat_mul(done_1),
    .address_mat_a(address_mat_a), 
    .address_mat_b(address_mat_b), 
    .address_mat_c(address_mat_c),
    .address_stride_a(address_stride_a), 
    .address_stride_b(address_stride_b), 
    .address_stride_c(address_stride_c),
    .a_data(ZERO),     
     .b_data(b_right_data),
    .a_data_in(a_out_0),   
    .b_data_in(ZERO),
    .c_data_in(c_out_0),  
    .c_data_out(c_out_1),
    .a_data_out(a_out_1),  
    .b_data_out(b_out_1),
    .a_addr(aa_1), 
    .b_addr(ba_1), 
    .c_addr(ca_1),
    .c_data_available(cv_1),
    .validity_mask_a_rows(4'b1111), 
    .validity_mask_a_cols_b_rows(4'b1111), 
    .validity_mask_b_cols(4'b1111),
    .final_mat_mul_size(8'd8), 
     .a_loc(8'd0), 
    .b_loc(8'd1),
    .flags(flags_1)
  );
 
  //bottom left block 
  
  matmul_4x4_systolic dut10 (
    .clk(clk), 
    .reset(reset), 
    .pe_reset(pe_reset),
    .start_mat_mul(start_mat_mul), 
    .done_mat_mul(done_2),
    .address_mat_a(address_mat_a), 
    .address_mat_b(address_mat_b), .address_mat_c(address_mat_c),
    .address_stride_a(address_stride_a), 
    .address_stride_b(address_stride_b), 
    .address_stride_c(address_stride_c),
    .a_data(a_bot_data),   
     .b_data(ZERO),
    .a_data_in(ZERO),  
    .b_data_in(b_out_0),
    .c_data_in(ZERO),   
    .c_data_out(c_out_2),
    .a_data_out(a_out_2),  
    .b_data_out(b_out_2),
    .a_addr(aa_2), 
    .b_addr(ba_2), 
    .c_addr(ca_2),
    .c_data_available(cv_2),
    .validity_mask_a_rows(4'b1111), 
    .validity_mask_a_cols_b_rows(4'b1111), 
    .validity_mask_b_cols(4'b1111),
    .final_mat_mul_size(8'd8), 
     .a_loc(8'd1), 
    .b_loc(8'd0),
    .flags(flags_2)
  );
 
  //the bottom right most one 
  
  matmul_4x4_systolic dut11 (
    .clk(clk), 
    .reset(reset), 
    .pe_reset(pe_reset),
    .start_mat_mul(start_mat_mul), 
    .done_mat_mul(done_3),
    .address_mat_a(address_mat_a), 
    .address_mat_b(address_mat_b), 
    .address_mat_c(address_mat_c),
    .address_stride_a(address_stride_a), 
    .address_stride_b(address_stride_b), 
    .address_stride_c(address_stride_c),
    .a_data(ZERO),     
     .b_data(ZERO),
    .a_data_in(a_out_2),   
    .b_data_in(b_out_1),
    .c_data_in(c_out_2),  
    .c_data_out(c_out_3),
    .a_data_out(a_out_3),  
    .b_data_out(b_out_3),
    .a_addr(aa_3), 
    .b_addr(ba_3), 
    .c_addr(ca_3),
    .c_data_available(cv_3),
    .validity_mask_a_rows(4'b1111), 
    .validity_mask_a_cols_b_rows(4'b1111), 
    .validity_mask_b_cols(4'b1111),
    .final_mat_mul_size(8'd8), 
     .a_loc(8'd1), 
    .b_loc(8'd1),
    .flags(flags_3)
  );
  // combined exception flag of the whole 8x8 array
  assign flags = flags_0 | flags_1 | flags_2 | flags_3;

  assign a_addr = aa_0;
  assign b_addr = ba_0;
 
  assign c_data_out       = {c_out_3, c_out_1};   

   localparam NUM_WORDS = 8;
 logic [3:0] wr_cnt;
 
  always_ff @(posedge clk) begin
    if (reset || !start_mat_mul) begin
      wr_cnt        <= 4'd0;
      done_mat_mul  <= 1'b0;
    end else begin
      done_mat_mul <= 1'b0;
      if (cv_0 && (wr_cnt < NUM_WORDS)) begin
        wr_cnt <= wr_cnt + 4'd1;
        if (wr_cnt == NUM_WORDS - 1) done_mat_mul <= 1'b1;   // pulse right after 8th write
      end
    end
  end

  assign c_addr           = ca_0 - (address_stride_c << 1);   // undo the +2*stride from the early done
  assign c_data_available = cv_0 && (wr_cnt < NUM_WORDS);
 

endmodule
