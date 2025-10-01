
SHELL := /bin/zsh

SIZE := 64
SVG := $(wildcard *.svg)
PNG := $(SVG:.svg=.png)

.PHONY: all clean

all: $(PNG)

%.png: %.svg
	rsvg-convert -a -w $(SIZE) -h $(SIZE) --dpi-x 96 --dpi-y 96 -o $@ $<
	magick "$@" -filter Lanczos -resize $(SIZE)x$(SIZE) -fill white -opaque black "$@"

clean:
	rm -f $(PNG)
