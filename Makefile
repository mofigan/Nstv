BINDIR=~/bin

all:
	cat nstv.yaml | sed 's/area=.../area=008/' > nstv.yaml.sample

install:
	cp nstv nstv.yaml $(BINDIR)

push:
	git push git@github.com:mofigan/Nstv.git master

clean:
	rm -f nstv_20*.tsv nstv_cache.html
