# Verdi (nWave) startup script for Lab 3 Part 4.
# Loaded by `make waves` with:
#   verdi -dbdir ... -ssf matmul_apb.fsdb -play part4_views.tcl
#
# Opens the exception (overflow) test with the signal groups the report needs:
#   1 APB bus          writes and reads
#   2 Config registers the registers after configuration, and start
#   3 Matmul running   start held, writes into C, done pulse, exception flags
#   4 Status registers the sticky DONE/FLAGS bits that the CPU reads back
# Markers are placed from WAVE_EVENT lines the testbench prints (the Makefile
# writes them to the file named by $WAVE_EVENTS). Times are in ns.
#
# Every Verdi command goes through "safe" so that a command this Verdi version
# does not accept prints a warning instead of stopping the script.

proc safe {args} {
    if {[catch {uplevel #0 $args} err]} {
        puts "part4_views.tcl WARNING: $args -> $err"
        return ""
    }
    return $err
}

# ---- Waveform window ---------------------------------------------------------
set win ""
foreach name {_nWave3 _nWave2 _nWave1} {
    if {$win eq "" && [info exists ::$name]} { set win [set ::$name] }
}
if {$win eq ""} {
    safe wvCreateWindow
    foreach name {_nWave3 _nWave2 _nWave1} {
        if {$win eq "" && [info exists ::$name]} { set win [set ::$name] }
    }
}
if {$win eq ""} {
    puts "part4_views.tcl: no nWave window found. Open one (File > New Waveform) and run:  source part4_views.tcl"
    return
}
safe wvSetWindowTimeUnit -win $win 1 ns

# ---- Signals -----------------------------------------------------------------
# {path width}. Vectors are added with their range, as Verdi names them.
set tb  "/matmul_with_ram_tb"
set dut "$tb/dut"
set apb "$dut/u_apb_slave"
set mm  "$dut/u_matmul_8x8"

# The v_* signals are [0:0] mirrors of one-bit signals declared in the
# testbench: Verdi only loads one-bit signals by a ranged name.
set groups [list \
  [list "1_APB_BUS" [list \
      "$tb/test_name 224" \
      "$tb/v_clk 1" \
      "$tb/v_PSEL 1" "$tb/v_PENABLE 1" "$tb/v_PWRITE 1" \
      "$tb/PADDR 4" "$tb/PWDATA 16" "$tb/PRDATA 16" "$tb/v_PREADY 1"]] \
  [list "2_CONFIG_REGS" [list \
      "$apb/address_mat_a 10" "$apb/address_mat_b 10" "$apb/address_mat_c 10" \
      "$apb/address_stride_a 8" "$apb/address_stride_b 8" "$apb/address_stride_c 8" \
      "$tb/v_start 1"]] \
  [list "3_MATMUL_RUNNING" [list \
      "$tb/v_start_mat_mul 1" "$tb/v_c_data_available 1" "$tb/v_done_mat_mul 1" \
      "$tb/v_flags_0 1" "$tb/v_flags_1 1" "$tb/v_flags_2 1" "$tb/v_flags_3 1" "$tb/v_flags 1"]] \
  [list "4_STATUS_REGS" [list \
      "$tb/v_done_q 1" "$tb/v_flags_q 1"]] \
]

safe wvGetSignalOpen -win $win
foreach g $groups {
    lassign $g title sigs
    set items [list $title]
    foreach s $sigs {
        lassign $s p w
        set p [format {%s[%d:0]} $p [expr {$w - 1}]]
        safe wvGetSignalSetScope -win $win [file dirname $p]
        lappend items $p
    }
    safe wvAddSignal -win $win -group $items
}
safe wvGetSignalClose -win $win

# Hex for the buses, ASCII for the test name.
foreach p {PADDR PWDATA PRDATA} {
    safe wvSetRadix -win $win -format Hex "$tb/$p"
}
safe wvSetRadix -win $win -format Ascii "$tb/test_name"

# ---- Markers and zoom --------------------------------------------------------
# events.tcl defines  events  as a dict: cfg_start, start_write, done_read, end
set ev [dict create]
if {[info exists ::env(WAVE_EVENTS)] && [file exists $::env(WAVE_EVENTS)]} {
    source $::env(WAVE_EVENTS)
    set ev $events
}
foreach {key label} {cfg_start CONFIG_WRITES start_write START_WRITE done_read DONE_READ end END} {
    if {[dict exists $ev $key]} {
        safe wvSetMarker -win $win -keepViewRange -name $label [dict get $ev $key]
    }
}
if {[dict exists $ev cfg_start] && [dict exists $ev end]} {
    safe wvZoom -win $win [expr {[dict get $ev cfg_start] - 20}] [expr {[dict get $ev end] + 20}]
} else {
    safe wvZoomAll -win $win
}
puts "part4_views.tcl: loaded (exception test)."
