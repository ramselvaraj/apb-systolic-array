`timescale 1ns/1ns

module matmul_with_ram_tb;

  reg clk;
  reg resetn;
  reg pe_resetn;

  // APB master signals
  reg         PSEL, PENABLE, PWRITE;
  reg  [3:0]  PADDR;
  reg  [15:0] PWDATA;
  wire [15:0] PRDATA;
  wire        PREADY;

  reg  [9:0]  addr_a_ext, addr_b_ext, addr_c_ext;
  reg  [63:0] wdata_a_ext, wdata_b_ext, wdata_c_ext;
  reg  [3:0]  we_a_ext, we_b_ext, we_c_ext;
  wire [63:0] rdata_a_ext, rdata_b_ext, rdata_c_ext;

  matrix_multiplication dut (
    .PCLK(clk),
    .PRESETn(resetn),
    .pe_resetn(pe_resetn),
    .PADDR(PADDR),
    .PWRITE(PWRITE),
    .PSEL(PSEL),
    .PENABLE(PENABLE),
    .PWDATA(PWDATA),
    .PRDATA(PRDATA),
    .PREADY(PREADY),
    .bram_addr_a_ext(addr_a_ext),
    .bram_rdata_a_ext(rdata_a_ext),
    .bram_wdata_a_ext(wdata_a_ext),
    .bram_we_a_ext(we_a_ext),
    .bram_addr_b_ext(addr_b_ext),
    .bram_rdata_b_ext(rdata_b_ext),
    .bram_wdata_b_ext(wdata_b_ext),
    .bram_we_b_ext(we_b_ext),
    .bram_addr_c_ext(addr_c_ext),
    .bram_rdata_c_ext(rdata_c_ext),
    .bram_wdata_c_ext(wdata_c_ext),
    .bram_we_c_ext(we_c_ext)
  );

  // Verdi in this setup only loads one-bit signals that are declared as
  // [0:0] vectors, so the one-bit signals shown in the waveform are mirrored
  // here (part4_views.tcl adds these v_* signals).
  wire [0:0] v_clk              = clk;
  wire [0:0] v_PSEL             = PSEL;
  wire [0:0] v_PENABLE          = PENABLE;
  wire [0:0] v_PWRITE           = PWRITE;
  wire [0:0] v_PREADY           = PREADY;
  wire [0:0] v_start            = dut.u_apb_slave.start;
  wire [0:0] v_done_q           = dut.u_apb_slave.done_q;
  wire [0:0] v_flags_q          = dut.u_apb_slave.flags_q;
  wire [0:0] v_start_mat_mul    = dut.start_mat_mul;
  wire [0:0] v_c_data_available = dut.u_matmul_8x8.c_data_available;
  wire [0:0] v_done_mat_mul     = dut.u_matmul_8x8.done_mat_mul;
  wire [0:0] v_flags_0          = dut.u_matmul_8x8.flags_0;
  wire [0:0] v_flags_1          = dut.u_matmul_8x8.flags_1;
  wire [0:0] v_flags_2          = dut.u_matmul_8x8.flags_2;
  wire [0:0] v_flags_3          = dut.u_matmul_8x8.flags_3;
  wire [0:0] v_flags            = dut.u_matmul_8x8.flags;

  // Register map (see apb_slave.sv)
  localparam [3:0] REG_CTRL     = 4'h0,
                   REG_ADDR_A   = 4'h1,
                   REG_ADDR_B   = 4'h2,
                   REG_ADDR_C   = 4'h3,
                   REG_STRIDE_A = 4'h4,
                   REG_STRIDE_B = 4'h5,
                   REG_STRIDE_C = 4'h6,
                   REG_DONE     = 4'h7,
                   REG_FLAGS    = 4'h8;


  // Raw FP8 override: when use_raw is set, load_matrices writes araw/braw
  // (A[i][k] at araw[i*8+k], B[k][j] at braw[k*8+j]) instead of ah/bh.
  reg       use_raw;
  reg [7:0] araw [0:63];
  reg [7:0] braw [0:63];

`ifdef FSDB
  initial begin
    $fsdbDumpfile("matmul_apb.fsdb");
    $fsdbDumpvars(0, matmul_with_ram_tb, "+all");
  end
`endif
`ifdef VCD
  initial begin
    $dumpfile("matmul_apb.vcd");
    $dumpvars(0, matmul_with_ram_tb);
  end
`endif

  initial clk = 0;
  always #5 clk = ~clk;

  // ---------------- test matrices (halves: 0, 1, 2 = 0, 0.5, 1.0) ----------------
  integer ah [0:63];     // A[i][k] at ah[i*8+k]
  integer bh [0:63];     // B[k][j] at bh[k*8+j]
  integer seed;

  function [7:0] half_to_fp;
    input integer h;
    begin
      case (h)
        0:       half_to_fp = 8'h00;
        1:       half_to_fp = 8'h20;   // 0.5
        default: half_to_fp = 8'h30;   // 1.0
      endcase
    end
  endfunction

  // n in quarter units (0..32) -> E3M4
  function [7:0] enc_units;
    input integer n;
    integer p;
    reg [2:0] e;
    reg [3:0] m;
    begin
      if (n == 0) enc_units = 8'h00;
      else begin
        p = 0;
        while ((n >> (p + 1)) != 0) p = p + 1;
        e = p + 1;
        m = (p <= 4) ? ((n - (1 << p)) << (4 - p)) : 4'd0;
        enc_units = {1'b0, e, m};
      end
    end
  endfunction

  function [63:0] expected_word;
    input integer j;
    integer i, k, sum;
    reg [63:0] w;
    begin
      w = 64'd0;
      for (i = 0; i < 8; i = i + 1) begin
        sum = 0;
        for (k = 0; k < 8; k = k + 1) sum = sum + ah[i*8+k] * bh[k*8+j];
        w[8*i +: 8] = enc_units(sum);
      end
      expected_word = w;
    end
  endfunction

  // Which column of C is stored in C word w?
  // Chain: dut00 -> dut01 and dut10 -> dut11, output taken from dut01/dut11,
  // so the right block (columns 4-7) comes out first.
  // Define OLD_C_ORDER for column j in word j.
  function integer col_for_word;
    input integer w;
    begin
`ifdef OLD_C_ORDER
      col_for_word = w;
`else
      col_for_word = (w < 4) ? (w + 4) : (w - 4);
`endif
    end
  endfunction

  function integer rnd3;
    input dummy;
    begin
      rnd3 = ($random(seed) & 32'h7fffffff) % 3;
    end
  endfunction

  // ---------------- APB master tasks ----------------
  // Signals change on negedge and are sampled by the slave on posedge.
  // SETUP: PSEL=1; ACCESS: PSEL=1 and PENABLE=1 (the slave acts on this edge).
  task apb_write(input [3:0] addr, input [15:0] data);
    begin
      @(negedge clk);
      PSEL = 1; PWRITE = 1; PADDR = addr; PWDATA = data;
      @(negedge clk);
      PENABLE = 1;
      @(negedge clk);
      PSEL = 0; PENABLE = 0; PWRITE = 0; PADDR = 0; PWDATA = 0;
    end
  endtask

  task apb_read(input [3:0] addr, output [15:0] data);
    begin
      @(negedge clk);
      PSEL = 1; PWRITE = 0; PADDR = addr;
      @(negedge clk);
      PENABLE = 1;
      @(negedge clk);
      data = PRDATA;
      PSEL = 0; PENABLE = 0; PADDR = 0;
    end
  endtask

  // ---------------- matrix generators ----------------
  task set_const;
    input integer av;
    input integer bv;
    integer x;
    begin
      for (x = 0; x < 64; x = x + 1) begin ah[x] = av; bh[x] = bv; end
    end
  endtask

  task set_random;
    integer x;
    begin
      for (x = 0; x < 64; x = x + 1) begin ah[x] = rnd3(0); bh[x] = rnd3(0); end
    end
  endtask

  task set_identity_a;
    integer i, j;
    begin
      for (i = 0; i < 8; i = i + 1)
        for (j = 0; j < 8; j = j + 1) ah[i*8+j] = (i == j) ? 2 : 0;
    end
  endtask

  task set_identity_b;
    integer i, j;
    begin
      for (i = 0; i < 8; i = i + 1)
        for (j = 0; j < 8; j = j + 1) bh[i*8+j] = (i == j) ? 2 : 0;
    end
  endtask

  // worked example: A lower-triangular of 1.0, B = 0.5 for cols 0-3, 1.0 for cols 4-7
  task set_example;
    integer i, k;
    begin
      for (i = 0; i < 8; i = i + 1)
        for (k = 0; k < 8; k = k + 1) begin
          ah[i*8+k] = (k <= i) ? 2 : 0;
          bh[i*8+k] = (k < 4)  ? 1 : 2;   // second index is the column here
        end
    end
  endtask

  // every element 15.5 (0x6F): each product is 240, far above the E3M4 max,
  // so the multiplier raises overflow
  task set_overflow;
    integer x;
    begin
      for (x = 0; x < 64; x = x + 1) begin
        araw[x] = 8'h6F;
        braw[x] = 8'h6F;
      end
    end
  endtask

  // ---------------- initialize the RAMs through the external ports ----------------
  // Writes A and B (one 64-bit word per address) and fills C with 0xFF sentinels
  // so that a C word that is never written shows up as a mismatch.
  // Base addresses of A, B and C in their RAMs (written to the ADDR registers)
  reg [9:0] a_base, b_base, c_base;

  task load_matrices;
    integer i, k;
    reg [63:0] wa, wb;
    begin
      for (k = 0; k < 8; k = k + 1) begin
        wa = 64'd0;
        wb = 64'd0;
        for (i = 0; i < 8; i = i + 1) begin
          wa[8*i +: 8] = use_raw ? araw[i*8+k] : half_to_fp(ah[i*8+k]);   // column k of A
          wb[8*i +: 8] = use_raw ? braw[k*8+i] : half_to_fp(bh[k*8+i]);   // row k of B
        end
        @(negedge clk);
        addr_a_ext  = a_base + k;  wdata_a_ext = wa;                  we_a_ext = 4'b1111;
        addr_b_ext  = b_base + k;  wdata_b_ext = wb;                  we_b_ext = 4'b1111;
        addr_c_ext  = c_base + k;  wdata_c_ext = {8{8'hFF}};          we_c_ext = 4'b1111;
      end
      @(negedge clk);
      we_a_ext = 4'b0000;
      we_b_ext = 4'b0000;
      we_c_ext = 4'b0000;
    end
  endtask

  // ---------------- run one test ----------------
  integer pass_cnt;
  integer fail_cnt;

  // name of the running test, shown as ASCII in the waveform
  reg [8*28-1:0] test_name;

  task run_test;
    input [8*28-1:0] name;
    input expect_flag;   // 1: exception expected, only the flag is checked
    integer j, i, cyc, errs, shown;
    reg done_seen;
    reg [15:0] rd, flag_rd;
    reg [63:0] ew, got;
    begin
      test_name = name;
      // PE reset while idle
      @(negedge clk);
      pe_resetn = 1'b0;
      repeat (2) @(negedge clk);
      pe_resetn = 1'b1;
      repeat (2) @(negedge clk);

      load_matrices;

      // WAVE_EVENT lines are picked up by the Makefile for the Verdi markers
      if (expect_flag) $display("WAVE_EVENT cfg_start %0d", $time);

      // configure over APB, then start
      apb_write(REG_ADDR_A,   a_base);
      apb_write(REG_ADDR_B,   b_base);
      apb_write(REG_ADDR_C,   c_base);
      apb_write(REG_STRIDE_A, 16'd1);
      apb_write(REG_STRIDE_B, 16'd1);
      apb_write(REG_STRIDE_C, 16'd1);
      if (expect_flag) $display("WAVE_EVENT start_write %0d", $time);
      apb_write(REG_CTRL,     16'd1);

      // poll DONE
      cyc = 0;
      done_seen = 1'b0;
      while (!done_seen && cyc < 100) begin
        apb_read(REG_DONE, rd);
        cyc = cyc + 1;
        if (rd[0]) done_seen = 1'b1;
      end
      if (expect_flag) $display("WAVE_EVENT done_read %0d", $time);
      apb_read(REG_FLAGS, flag_rd);
      repeat (4) @(negedge clk);
      if (expect_flag) $display("WAVE_EVENT end %0d", $time);

      // read C back and compare
      errs = 0;
      shown = 0;
      if (!done_seen) begin
        errs = errs + 1;
        $display("  [%0s] done never asserted", name);
      end
      // exception flag must match the scenario
      if (flag_rd[0] !== expect_flag) begin
        errs = errs + 1;
        $display("  [%0s] flag mismatch: expected %0b, got %0b", name, expect_flag, flag_rd[0]);
      end
      for (j = 0; (j < 8) && !expect_flag; j = j + 1) begin
        @(negedge clk);
        addr_c_ext = c_base + j;
        we_c_ext   = 4'b0000;
        @(negedge clk);
        @(negedge clk);
        got = rdata_c_ext;
        ew  = expected_word(col_for_word(j));
        if (got !== ew) begin
          for (i = 0; i < 8; i = i + 1) begin
            if (got[8*i +: 8] !== ew[8*i +: 8]) begin
              errs = errs + 1;
              if (shown < 8) begin
                shown = shown + 1;
                $display("  [%0s] MISMATCH C[%0d][%0d]: expected 0x%02h, got 0x%02h",
                         name, i, col_for_word(j), ew[8*i +: 8], got[8*i +: 8]);
              end
            end
          end
        end
      end

      if (errs == 0) begin
        pass_cnt = pass_cnt + 1;
        $display("PASS  %0s (DONE polled %0d times)", name, cyc);
      end else begin
        fail_cnt = fail_cnt + 1;
        $display("FAIL  %0s (DONE polled %0d times, %0d errors)", name, cyc, errs);
      end
    end
  endtask

  // ---------------- main ----------------
  integer t;
  initial begin
    pass_cnt = 0;
    fail_cnt = 0;
    seed = 32'h1234abcd;
    resetn = 1'b0;
    pe_resetn = 1'b0;
    PSEL = 0; PENABLE = 0; PWRITE = 0; PADDR = 0; PWDATA = 0;
    use_raw = 1'b0;
    a_base = 0; b_base = 0; c_base = 0;
    addr_a_ext = 0; addr_b_ext = 0; addr_c_ext = 0;
    wdata_a_ext = 0; wdata_b_ext = 0; wdata_c_ext = 0;
    we_a_ext = 0; we_b_ext = 0; we_c_ext = 0;

    $display("---- matmul_with_ram (8x8, FP8 E3M4) testbench ----");
    repeat (5) @(negedge clk);
    resetn = 1'b1;
    pe_resetn = 1'b1;
    repeat (2) @(negedge clk);

    set_const(0, 0);                      run_test("all zeros", 1'b0);
    set_const(2, 2);                      run_test("all ones (C = 8.0)", 1'b0);
    set_example;                          run_test("worked example", 1'b0);
    set_random; set_identity_b;           run_test("B = identity (C = A)", 1'b0);
    set_random; set_identity_a;           run_test("A = identity (C = B)", 1'b0);
    for (t = 0; t < 10; t = t + 1) begin
      set_random;                         run_test("random {0,0.5,1.0}", 1'b0);
    end

    // non-zero base addresses: proves the ADDR registers really steer the matmul
    a_base = 16; b_base = 32; c_base = 48;
    set_random;                           run_test("non-zero base addresses", 1'b0);

    // exception case: overflow must assert flags. Reset first so the APB
    // registers start at 0 and visibly take their values in the waveform.
    @(negedge clk); resetn = 1'b0;
    repeat (3) @(negedge clk);
    resetn = 1'b1;
    set_overflow; use_raw = 1'b1;         run_test("overflow (flag expected)", 1'b1);
    use_raw = 1'b0;

    $display("----");
    $display("%0d passed, %0d failed", pass_cnt, fail_cnt);
    if (fail_cnt == 0) $display("ALL TESTS PASSED");
    else               $display("TESTS FAILED");
    $finish;
  end

  initial begin
    #5000000;
    $display("GLOBAL TIMEOUT");
    $finish;
  end

endmodule