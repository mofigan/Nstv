BINDIR=~/bin

sample:
	cat nstv.yaml | sed 's/area=.../area=008/' > nstv.yaml.sample
	cat nsrename.yaml | sed 's/\/.\//\//' | grep -v Pool | grep -v '\- \^' | grep -v '\+\$$' > nsrename.yaml.sample

install:
	cp nstv nstv.yaml $(BINDIR)

push:
	git push git@github.com:mofigan/Nstv.git master

clean:
	rm -f nstv_20*.tsv
