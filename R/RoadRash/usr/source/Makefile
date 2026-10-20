include ../../options.mk

PROGNAME = RoadRash


WHDLOADER = $(PROGNAME).slave
SOURCE = $(PROGNAME)HD.s

all :  $(WHDLOADER)

$(WHDLOADER) : $(SOURCE) ReadJoypad.s verify.s
	$(WDATE)
	$(VASM) -o $(WHDLOADER) $(SOURCE)
