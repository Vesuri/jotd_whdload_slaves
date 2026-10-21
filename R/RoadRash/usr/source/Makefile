AMIGA_SHARE ?= $(HOME)/.local/share/amiga
VASM ?= $(HOME)/.local/vasmm68k_mot
VASMFLAGS = -quiet -devpac -nosym -Fhunkexe -pic -I"$(AMIGA_SHARE)/WHDLoad/Include" -I"$(AMIGA_SHARE)/WHDLoad/Src" -I"$(AMIGA_SHARE)/ndk/Include_I" -I.
ORIGINAL ?= ../../../../tmp/dev/tmp/archives/RoadRash.lha
OUT ?= ../../../../tmp/dev/tmp/release-3.0b

.PHONY: all dist clean
all: RoadRash.slave

RoadRash.slave: $(wildcard *.s)
	"$(VASM)" $(VASMFLAGS) -o "$@" RoadRashHD.s

dist:
	AMIGA_SHARE="$(AMIGA_SHARE)" VASM="$(VASM)" python3 package_release.py --original "$(ORIGINAL)" --output "$(OUT)"

clean:
	rm -f RoadRash.slave
