include ../../options.mk

PROGNAME = RoadRash


WHDLOADER = $(PROGNAME).slave
SOURCE = $(PROGNAME)HD.s

all :  $(WHDLOADER)

$(WHDLOADER) : $(SOURCE) ReadJoypad.s verify.s verify_b.s verify_c_audit.s simulation.s verify_c_events.s verify_c_latency.s steering.s runtime_stack.s
	$(WDATE)
	$(VASM) -o $(WHDLOADER) $(SOURCE)
