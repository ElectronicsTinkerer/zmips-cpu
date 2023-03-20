#!/bin/bash -e

vlog -work work ../verilog/*.sv
vsim -c tb_zmips -do "run 500; exit"


