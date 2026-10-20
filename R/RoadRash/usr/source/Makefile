include ../../options.mk

PROGNAME = RoadRash


WHDLOADER = $(PROGNAME).slave
SOURCE = $(PROGNAME)HD.s

all :  $(WHDLOADER)

$(WHDLOADER) : $(SOURCE) ReadJoypad.s verify.s verify_b.s verify_c_audit.s
	$(WDATE)
	$(VASM) -o $(WHDLOADER) $(SOURCE)
