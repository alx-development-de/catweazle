.PHONY : all clean clean-temp

MAIN_SOURCE = catweazle.tex

all: pdf

pdf: $(MAIN_SOURCE) aux toc
	lualatex $<

aux: $(MAIN_SOURCE)
	lualatex $<

toc: $(MAIN_SOURCE)
	lualatex $<

clean: clean-temp
	-rm *.pdf

clean-temp:
	-rm -rf _markdown_*
	-rm *.ps
	-rm *.dvi
	-rm *.toc
	-rm *.aux
	-rm *.log
	-rm *.out
	-rm *.lof
	-rm *.bib~*
	-rm *.bbl
	-rm *.blg
	-rm *.lol
	-rm *.lot
	-rm *.synctex.gz
