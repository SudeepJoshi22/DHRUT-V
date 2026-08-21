# Open-source build flow for the Sipeed Tang Nano 20K (GW2AR-18 / GW2AR-LV18QN88C8/I7)
# Requires OSS CAD Suite tools on your PATH: yosys, nextpnr-himbaechel, gowin_pack, openFPGALoader
#
# Usage:
#   make          -> synthesize + place-and-route + pack bitstream (produces blink.fs)
#   make flash    -> flash blink.fs to the board's SRAM (temporary, lost on power cycle)
#   make flash-nv -> flash blink.fs to the board's onboard flash (persists across power cycles)
#   make clean    -> remove generated files

TOP        = blink
DEVICE     = GW2AR-LV18QN88C8/I7
FAMILY     = GW2A-18C
CST        = tangnano20k.cst

SRC        = blink.v
JSON       = $(TOP).json
PACK_JSON  = pack.json
BITSTREAM  = $(TOP).fs

all: $(BITSTREAM)

$(JSON): $(SRC)
	yosys -p "read_verilog $(SRC); synth_gowin -top $(TOP) -json $(JSON)"

$(PACK_JSON): $(JSON) $(CST)
	nextpnr-himbaechel \
		--json $(JSON) \
		--write $(PACK_JSON) \
		--device $(DEVICE) \
		--vopt family=$(FAMILY) \
		--vopt cst=$(CST)

$(BITSTREAM): $(PACK_JSON)
	gowin_pack -d $(FAMILY) -o $(BITSTREAM) $(PACK_JSON)

flash: $(BITSTREAM)
	openFPGALoader -b tangnano20k $(BITSTREAM)

flash-nv: $(BITSTREAM)
	openFPGALoader -b tangnano20k -f $(BITSTREAM)

clean:
	rm -f $(JSON) $(PACK_JSON) $(BITSTREAM)

.PHONY: all flash flash-nv clean