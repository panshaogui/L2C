PROJECT = hdmi_test
TOP_MODULE = hdmi_top
DEVICE = GW1NR-LV9QN88PC6/I5
FAMILY = GW1N-9C

all: $(PROJECT).fs flash

$(PROJECT).json: top.v hdmi_blackbox.v
	yosys -p "read_verilog top.v hdmi_blackbox.v; synth_gowin -top $(TOP_MODULE) -json $@"

# 正确参数：使用 --family GW1N-9C
$(PROJECT)_pnr.json: $(PROJECT).json tangnano9k.cst
	nextpnr-gowin --device $(DEVICE) --family $(FAMILY) --json $< --write $@ --cst tangnano9k.cst

$(PROJECT).fs: $(PROJECT)_pnr.json
	gowin_pack -d $(FAMILY) $< -o $@

flash: $(PROJECT).fs
	openFPGALoader -b tangnano9k -f $(PROJECT).fs

clean:
	rm -f *.json *.fs