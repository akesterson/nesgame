SOURCE=nesgame.S \
	include/defines.S \
	include/math.S \
	include/graphics.S
MAIN_SOURCE=nesgame.S

all: nesgame.nes
nesgame.nes : $(SOURCE)
	ophis -o $(MAIN_SOURCE) $<

.PHONY: test
test: nesgame.nes
	fceux nesgame.nes

.PHONY: clean
clean:
	rm *nes

tags: $(SOURCE)
	find . -name "*S" | xargs etags -a
