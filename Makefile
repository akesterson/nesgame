all: nesgame.nes
nesgame.nes : nesgame.S
	ophis -o $@ $<

.PHONY: test
test:
	fceux nesgame.nes

.PHONY: clean
clean:
	rm *nes
	rm *nes.deb
	rm *fns
