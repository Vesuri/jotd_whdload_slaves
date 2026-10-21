include ../../options.mk

PROGNAME = RoadRash


WHDLOADER = $(PROGNAME).slave
SOURCE = $(PROGNAME)HD.s

all :  $(WHDLOADER)

$(WHDLOADER) : $(SOURCE) ReadJoypad.s verify.s verify_b.s verify_c_audit.s simulation.s verify_c_events.s verify_c_latency.s steering.s runtime_stack.s physics_fast.s physics_aux.s road_timing.s collision_geometry.s lean_pose.s raster_edge.s reference_motion.s
	$(WDATE)
	$(VASM) -o $(WHDLOADER) $(SOURCE)
