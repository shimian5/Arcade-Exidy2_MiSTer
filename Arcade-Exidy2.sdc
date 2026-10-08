## Exidy2 project timing constraints

## Copyright (C) 2017  Intel Corporation. All rights reserved.
## Your use of Intel Corporation's design tools, logic functions 
## and other software and tools, and its AMPP partner logic 
## functions, and any output files from any of the foregoing 
## (including device programming or simulation files), and any 
## associated documentation or information are expressly subject 
## to the terms and conditions of the Intel Program License 
## Subscription Agreement, the Intel Quartus Prime License Agreement,
## the Intel MegaCore Function License Agreement, or other 
## applicable license agreement, including, without limitation, 
## that your use is for the sole purpose of programming logic 
## devices manufactured by Intel and sold by Intel or its 
## authorized distributors.  Please refer to the applicable 
## agreement for further details.


## VENDOR  "Altera"
## PROGRAM "Quartus Prime"
## VERSION "Version 17.0.2 Build 602 07/19/2017 SJ Lite Edition"

## DATE    "Fri Jun 02 15:36:51 2023"

##
## DEVICE  "5CSEBA6U23I7"
##


#**************************************************************
# Time Information
#**************************************************************

set_time_format -unit ns -decimal_places 3



#**************************************************************
# Create Clock
#**************************************************************

create_clock -name {altera_reserved_tck} -period 33.333 -waveform { 0.000 16.666 } [get_ports {altera_reserved_tck}]
create_clock -name {FPGA_CLK1_50} -period 20.000 -waveform { 0.000 10.000 } [get_ports {FPGA_CLK1_50}]
create_clock -name {FPGA_CLK2_50} -period 20.000 -waveform { 0.000 10.000 } [get_ports {FPGA_CLK2_50}]
create_clock -name {FPGA_CLK3_50} -period 20.000 -waveform { 0.000 10.000 } [get_ports {FPGA_CLK3_50}]
create_clock -name {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk} -period 10.000 -waveform { 0.000 5.000 } [get_pins -compatibility_mode {*|h2f_user0_clk}]
create_clock -name {spi_sck} -period 10.000 -waveform { 0.000 5.000 } [get_pins -compatibility_mode {spi|sclk_out}]
create_clock -name {hdmi_sck} -period 100.000 -waveform { 0.000 50.000 } [get_pins -compatibility_mode {hdmi_i2c|out_clk}]


#**************************************************************
# Create Generated Clock
#**************************************************************

create_generated_clock -name {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk} -source [get_pins {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|vco0ph[0]}] -duty_cycle 50/1 -multiply_by 1 -divide_by 3 -master_clock {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|fpll_0|fpll|vcoph[0]} [get_pins {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}] 
create_generated_clock -name {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|fpll_0|fpll|vcoph[0]} -source [get_pins {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|fpll_0|fpll|refclkin}] -duty_cycle 50/1 -multiply_by 4563 -divide_by 512 -master_clock {FPGA_CLK1_50} [get_pins {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|fpll_0|fpll|vcoph[0]}] 


#**************************************************************
# Set Clock Latency
#**************************************************************



#**************************************************************
# Set Clock Uncertainty
#**************************************************************

# Fixed PLL clocks come from implemented IP; preserve nominal HDMI constraints above.
derive_pll_clocks
# Registered divider pulses are real clocks on legacy board registers.
# Source equations and fitted Q/source collections were independently checked.
# Keep their relationships timed; do not convert hold failures into exceptions.
proc exidy_counter_clock {name pll_index edges target_name} {
    set source_name [format {emu|pll|pll_inst|altera_pll_i|general[%d].gpll~PLL_OUTPUT_COUNTER|divclk} $pll_index]
    set source [get_pins $source_name]
    set parent [get_clocks $source_name]
    set target [get_pins $target_name]
    foreach collection [list $source $parent $target] {
        if {[get_collection_size $collection] != 1} {
            error "Expected one source, parent and target for Exidy counter clock $name"
        }
    }
    create_generated_clock -name $name -source $source -master_clock $parent -edges $edges $target
}
exidy_counter_clock BCLK   0 {1 3 17}    {emu|ex2|BCLK|q}
exidy_counter_clock PH_1   0 {63 65 191} {emu|ex2|PH_1|q}
exidy_counter_clock PH_6   0 {1 3 129}   {emu|ex2|PH_6|q}
exidy_counter_clock auPH0  2 {1 3 33}    {emu|ex2|sound_board|auPH0|q}
exidy_counter_clock auPH0B 2 {3 5 35}    {emu|ex2|sound_board|auPH0B|q}
rename exidy_counter_clock {}
derive_clock_uncertainty
set_clock_uncertainty -rise_from [get_clocks {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}] -rise_to [get_clocks {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}] -setup 0.200  
set_clock_uncertainty -rise_from [get_clocks {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}] -rise_to [get_clocks {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}] -hold 0.080  
set_clock_uncertainty -rise_from [get_clocks {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}] -fall_to [get_clocks {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}] -setup 0.200  
set_clock_uncertainty -rise_from [get_clocks {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}] -fall_to [get_clocks {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}] -hold 0.080  
set_clock_uncertainty -fall_from [get_clocks {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}] -rise_to [get_clocks {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}] -setup 0.200  
set_clock_uncertainty -fall_from [get_clocks {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}] -rise_to [get_clocks {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}] -hold 0.080  
set_clock_uncertainty -fall_from [get_clocks {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}] -fall_to [get_clocks {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}] -setup 0.200  
set_clock_uncertainty -fall_from [get_clocks {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}] -fall_to [get_clocks {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}] -hold 0.080  
set_clock_uncertainty -rise_from [get_clocks {altera_reserved_tck}] -rise_to [get_clocks {altera_reserved_tck}] -setup 0.310  
set_clock_uncertainty -rise_from [get_clocks {altera_reserved_tck}] -rise_to [get_clocks {altera_reserved_tck}] -hold 0.270  
set_clock_uncertainty -rise_from [get_clocks {altera_reserved_tck}] -fall_to [get_clocks {altera_reserved_tck}] -setup 0.310  
set_clock_uncertainty -rise_from [get_clocks {altera_reserved_tck}] -fall_to [get_clocks {altera_reserved_tck}] -hold 0.270  
set_clock_uncertainty -fall_from [get_clocks {altera_reserved_tck}] -rise_to [get_clocks {altera_reserved_tck}] -setup 0.310  
set_clock_uncertainty -fall_from [get_clocks {altera_reserved_tck}] -rise_to [get_clocks {altera_reserved_tck}] -hold 0.270  
set_clock_uncertainty -fall_from [get_clocks {altera_reserved_tck}] -fall_to [get_clocks {altera_reserved_tck}] -setup 0.310  
set_clock_uncertainty -fall_from [get_clocks {altera_reserved_tck}] -fall_to [get_clocks {altera_reserved_tck}] -hold 0.270  
set_clock_uncertainty -rise_from [get_clocks {FPGA_CLK2_50}] -rise_to [get_clocks {FPGA_CLK2_50}] -setup 0.170  
set_clock_uncertainty -rise_from [get_clocks {FPGA_CLK2_50}] -rise_to [get_clocks {FPGA_CLK2_50}] -hold 0.060  
set_clock_uncertainty -rise_from [get_clocks {FPGA_CLK2_50}] -fall_to [get_clocks {FPGA_CLK2_50}] -setup 0.170  
set_clock_uncertainty -rise_from [get_clocks {FPGA_CLK2_50}] -fall_to [get_clocks {FPGA_CLK2_50}] -hold 0.060  
set_clock_uncertainty -fall_from [get_clocks {FPGA_CLK2_50}] -rise_to [get_clocks {FPGA_CLK2_50}] -setup 0.170  
set_clock_uncertainty -fall_from [get_clocks {FPGA_CLK2_50}] -rise_to [get_clocks {FPGA_CLK2_50}] -hold 0.060  
set_clock_uncertainty -fall_from [get_clocks {FPGA_CLK2_50}] -fall_to [get_clocks {FPGA_CLK2_50}] -setup 0.170  
set_clock_uncertainty -fall_from [get_clocks {FPGA_CLK2_50}] -fall_to [get_clocks {FPGA_CLK2_50}] -hold 0.060  
set_clock_uncertainty -rise_from [get_clocks {spi_sck}] -rise_to [get_clocks {spi_sck}]  0.060  
set_clock_uncertainty -rise_from [get_clocks {spi_sck}] -fall_to [get_clocks {spi_sck}]  0.060  
set_clock_uncertainty -fall_from [get_clocks {spi_sck}] -rise_to [get_clocks {spi_sck}]  0.060  
set_clock_uncertainty -fall_from [get_clocks {spi_sck}] -fall_to [get_clocks {spi_sck}]  0.060  
set_clock_uncertainty -rise_from [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}] -rise_to [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}]  0.060  
set_clock_uncertainty -rise_from [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}] -fall_to [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}]  0.060  
set_clock_uncertainty -fall_from [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}] -rise_to [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}]  0.060  
set_clock_uncertainty -fall_from [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}] -fall_to [get_clocks {sysmem|fpga_interfaces|clocks_resets|h2f_user0_clk}]  0.060  
set_clock_uncertainty -rise_from [get_clocks {FPGA_CLK1_50}] -rise_to [get_clocks {FPGA_CLK1_50}] -setup 0.170  
set_clock_uncertainty -rise_from [get_clocks {FPGA_CLK1_50}] -rise_to [get_clocks {FPGA_CLK1_50}] -hold 0.060  
set_clock_uncertainty -rise_from [get_clocks {FPGA_CLK1_50}] -fall_to [get_clocks {FPGA_CLK1_50}] -setup 0.170  
set_clock_uncertainty -rise_from [get_clocks {FPGA_CLK1_50}] -fall_to [get_clocks {FPGA_CLK1_50}] -hold 0.060  
set_clock_uncertainty -fall_from [get_clocks {FPGA_CLK1_50}] -rise_to [get_clocks {FPGA_CLK1_50}] -setup 0.170  
set_clock_uncertainty -fall_from [get_clocks {FPGA_CLK1_50}] -rise_to [get_clocks {FPGA_CLK1_50}] -hold 0.060  
set_clock_uncertainty -fall_from [get_clocks {FPGA_CLK1_50}] -fall_to [get_clocks {FPGA_CLK1_50}] -setup 0.170  
set_clock_uncertainty -fall_from [get_clocks {FPGA_CLK1_50}] -fall_to [get_clocks {FPGA_CLK1_50}] -hold 0.060  


#**************************************************************
# Set Input Delay
#**************************************************************



#**************************************************************
# Set Output Delay
#**************************************************************



#**************************************************************
# Set Clock Groups
#**************************************************************

set_clock_groups -asynchronous -group [get_clocks {altera_reserved_tck}] 
set_clock_groups -exclusive -group [get_clocks { *|pll|pll_inst|altera_pll_i|*[*].*|divclk}] -group [get_clocks { pll_hdmi|pll_hdmi_inst|altera_pll_i|*[0].*|divclk}] -group [get_clocks { pll_audio|pll_audio_inst|altera_pll_i|*[0].*|divclk}] -group [get_clocks { spi_sck}] -group [get_clocks { hdmi_sck}] -group [get_clocks { *|h2f_user0_clk}] -group [get_clocks { FPGA_CLK1_50 }] -group [get_clocks { FPGA_CLK2_50 }] -group [get_clocks { FPGA_CLK3_50 }] 


#**************************************************************
# Set False Path
#**************************************************************

set_false_path -to [get_keepers {*altera_std_synchronizer:*|din_s1}]
set_false_path -from [get_ports {KEY*}] 
set_false_path -from [get_ports {BTN_*}] 
set_false_path -to [get_ports {LED_*}]
set_false_path -to [get_ports {VGA_*}]
set_false_path -to [get_ports {AUDIO_SPDIF}]
set_false_path -to [get_ports {AUDIO_L}]
set_false_path -to [get_ports {AUDIO_R}]
set_false_path -from [get_keepers {get_ports {SW[*]}}] 
set_false_path -to [get_keepers {cfg[*]}]
set_false_path -from [get_keepers {cfg[*]}] 
set_false_path -from [get_keepers {VSET[*]}] 
set_false_path -to [get_keepers {wcalc[*] hcalc[*]}]
set_false_path -to [get_keepers {hdmi_width[*] hdmi_height[*]}]
set_false_path -to [get_keepers {*_osd|v_cnt*}]
set_false_path -to [get_keepers {*_osd|v_osd_start*}]
set_false_path -to [get_keepers {*_osd|v_info_start*}]
set_false_path -to [get_keepers {*_osd|h_osd_start*}]
set_false_path -from [get_keepers {*_osd|v_osd_start*}] 
set_false_path -from [get_keepers {*_osd|v_info_start*}] 
set_false_path -from [get_keepers {*_osd|h_osd_start*}] 
set_false_path -from [get_keepers {*_osd|rot*}] 
set_false_path -from [get_keepers {*_osd|dsp_width*}] 
set_false_path -to [get_keepers {*_osd|half}]
set_false_path -to [get_keepers {WIDTH[*] HFP[*] HS[*] HBP[*] HEIGHT[*] VFP[*] VS[*] VBP[*]}]
set_false_path -from [get_keepers {WIDTH[*] HFP[*] HS[*] HBP[*] HEIGHT[*] VFP[*] VS[*] VBP[*]}] 
set_false_path -to [get_keepers {FB_BASE[*] FB_BASE[*] FB_WIDTH[*] FB_HEIGHT[*] LFB_HMIN[*] LFB_HMAX[*] LFB_VMIN[*] LFB_VMAX[*]}]
set_false_path -from [get_keepers {FB_BASE[*] FB_BASE[*] FB_WIDTH[*] FB_HEIGHT[*] LFB_HMIN[*] LFB_HMAX[*] LFB_VMIN[*] LFB_VMAX[*]}] 
set_false_path -to [get_keepers {vol_att[*] scaler_flt[*] led_overtake[*] led_state[*]}]
set_false_path -from [get_keepers {vol_att[*] scaler_flt[*] led_overtake[*] led_state[*]}] 
set_false_path -from [get_keepers {aflt_* acx* acy* areset* arc*}] 
set_false_path -from [get_keepers {arx* ary*}] 
set_false_path -from [get_keepers {vs_line*}] 
set_false_path -from [get_keepers {ascal|o_ihsize*}] 
set_false_path -from [get_keepers {ascal|o_ivsize*}] 
set_false_path -from [get_keepers {ascal|o_format*}] 
set_false_path -from [get_keepers {ascal|o_hdown}] 
set_false_path -from [get_keepers {ascal|o_vdown}] 
set_false_path -from [get_keepers {ascal|o_hmin* ascal|o_hmax* ascal|o_vmin* ascal|o_vmax* ascal|o_vrrmax* ascal|o_vrr}] 
set_false_path -from [get_keepers {ascal|o_hdisp* ascal|o_vdisp*}] 
set_false_path -from [get_keepers {ascal|o_htotal* ascal|o_vtotal*}] 
set_false_path -from [get_keepers {ascal|o_hsstart* ascal|o_vsstart* ascal|o_hsend* ascal|o_vsend*}] 
set_false_path -from [get_keepers {ascal|o_hsize* ascal|o_vsize*}] 
set_false_path -from [get_keepers {mcp23009|sd_cd}] 


#**************************************************************
# Set Multicycle Path
#**************************************************************

set_multicycle_path -setup -end -to [get_keepers {*_osd|osd_vcnt*}] 2
set_multicycle_path -hold -end -to [get_keepers {*_osd|osd_vcnt*}] 1


#**************************************************************
# Set Maximum Delay
#**************************************************************



#**************************************************************
# Set Minimum Delay
#**************************************************************



#**************************************************************
# Set Input Transition
#**************************************************************

#**************************************************************
# Audio-board CPU handshake (main-CPU PIA 9B <-> audio-CPU PIA 8B)
#**************************************************************
# PIA_9B runs on the 45.15 MHz master clock and PIA_8B/T65 on the 14.37 MHz audio
# clock. These are different outputs of the same PLL, exchanging CA1/CB1/CA2/CB2 lines
# and bus data through a firmware protocol (as on the original board, where the
# two processors are asynchronous). The SDC puts both PLL outputs in one group,
# so their edge relationships must be modeled correctly. Historical runs
# failed under stale PLL constraints. Retain only the existing interface exceptions; other
# master/audio crossings remain timed.
set_false_path -from [get_keepers {*exidyAB:sound_board|pia6821:PIA_9B|*}] -to [get_keepers {*exidyAB:sound_board|pia6821:PIA_8B|* *exidyAB:sound_board|T65:A6502|*}]
set_false_path -from [get_keepers {*exidyAB:sound_board|pia6821:PIA_8B|*}] -to [get_keepers {*exidyAB:sound_board|pia6821:PIA_9B|*}]

# Audio-clock reset: RESET_n (master clock / hps_io) is re-timed in exidyResetSync.
# Its first flop samples the cross-domain signal and is the synchronizer's
# metastability stage, so it is exempt from setup/hold; the second flop is timed.
set_false_path -to [get_keepers {*exidyAB:sound_board|exidyResetSync:audio_reset|rst_meta}]

# Pause is a held single-bit level sampled by a two-register audio-domain
# synchronizer. Only its first metastability stage may violate setup/hold;
# the stage-to-stage path and the ready/mute consumers remain timed. Force
# identification in RTL even though the two source PLL clocks are related.
set pause_first_stage [get_keepers {*exidyAB:sound_board|exidyPauseSync:audio_pause|pause_meta}]
if {[get_collection_size $pause_first_stage] != 1} {
    error "Expected exactly one audio pause first-stage register"
}
set_false_path -to $pause_first_stage

# Hardware-profile byte (MRA index 1, mod_other) is written only while a file is
# downloading, with the core held in reset, then is static. The audio board reads
# it (pcb[4] etc.) on the 14.37 MHz audio clock, so constrain only these
# configuration-to-audio-board paths.
set_false_path -from [get_keepers {*emu|mod_other[*]}] -to [get_keepers {*exidyAB:sound_board|*}]

# Bundled PIA snapshots: add only after the existing project constraints.
# The FIFO publishes each write through a two-stage Gray-pointer synchronizer.
# Destination capture is at least two master periods after the source write;
# 20 ns is below that ~44.3 ns window, including reported clock skew/uncertainty.
# Quartus 17 has no -datapath_only option. These are clock-relative bounds;
# review the fitted data delays as well as their slack. No bus false path.
proc pia_fifo_nodes {pattern count} {
    set nodes [get_keepers $pattern]
    if {[get_collection_size $nodes] != $count} {
        error "PIA FIFO expected $count nodes for $pattern, found [get_collection_size $nodes]"
    }
    return $nodes
}
set pia_fifo_words [pia_fifo_nodes {*exidyPiaReturn:pia_return_data|fifo_mem*} 36]
set pia_fifo_capture [pia_fifo_nodes {*exidyPiaReturn:pia_return_data|main_byte_data[*] *exidyPiaReturn:pia_return_data|pending_notify_value} 9]
set_max_delay -from $pia_fifo_words -to $pia_fifo_capture 20.000
# Gray bus routing is shorter than either source period. First synchronizer
# stages may encounter metastability; stage-to-stage paths stay normally timed.
proc pia_fifo_gray_nodes {name} {
    set pattern [format {*exidyPiaReturn:pia_return_data|%s[*]} $name]
    set nodes [get_registers $pattern]
    set bits {}
    set expression [format {\|%s\[([0-2])\](~DUPLICATE[0-9]*)?$} $name]
    foreach_in_collection node $nodes {
        set full_name [get_register_info -name $node]
        if {![regexp $expression $full_name unused bit]} {
            error "Unexpected PIA FIFO Gray register: $full_name"
        }
        lappend bits $bit
    }
    if {[lsort -unique $bits] ne {0 1 2}} {
        error "PIA FIFO $name is missing logical bits: $bits"
    }
    # Include physical replicas in the bound; do not silently drop their paths.
    return $nodes
}
set pia_fifo_write [pia_fifo_gray_nodes write_gray]
set pia_fifo_read [pia_fifo_gray_nodes read_gray]
set pia_fifo_write_meta [pia_fifo_nodes {*exidyPiaReturn:pia_return_data|write_gray_meta[*]} 3]
set pia_fifo_read_meta [pia_fifo_nodes {*exidyPiaReturn:pia_return_data|read_gray_meta[*]} 3]
set_max_delay -from $pia_fifo_write -to $pia_fifo_write_meta 20.000
set_max_delay -from $pia_fifo_read -to $pia_fifo_read_meta 20.000
# Raw reset asserts both conditioner stages asynchronously. Except ONLY their
# asynchronous-clear input pins. Meta-to-release data and local release-to-state
# recovery/removal remain timed. This is the reset synchronizer input contract,
# not an exception on the synchronizer data chain or the FIFO state resets.
set pia_fifo_reset_pins [get_pins -compatibility_mode {*|pia_return_data|audio_reset_meta|clrn *|pia_return_data|audio_reset_release|clrn *|pia_return_data|master_reset_meta|clrn *|pia_return_data|master_reset_release|clrn}]
if {[get_collection_size $pia_fifo_reset_pins] != 4} {
    error "PIA FIFO expected exactly four conditioner clear pins"
}
set_false_path -through $pia_fifo_reset_pins
rename pia_fifo_nodes {}
rename pia_fifo_gray_nodes {}
