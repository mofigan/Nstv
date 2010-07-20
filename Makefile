BINDIR=~/bin

all:
	cat nstv.yaml | sed 's/area=.../area=008/' > nstv.yaml.sample

install:
	cp nstv nstv.yaml Nstv.pm $(BINDIR)

clean:
	rm -f nstv_20*.tsv nstv_cache.html
