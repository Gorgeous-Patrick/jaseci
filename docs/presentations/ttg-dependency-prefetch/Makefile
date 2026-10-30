.PHONY: all clean

all: ttg-dependency-prefetch.pdf

ttg-dependency-prefetch.pdf: slides.tex data/fixture-source.txt
	mkdir -p build
	pdflatex -interaction=nonstopmode -halt-on-error -output-directory=build slides.tex
	pdflatex -interaction=nonstopmode -halt-on-error -output-directory=build slides.tex
	cp build/slides.pdf $@

clean:
	rm -rf build
