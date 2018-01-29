
planner.img: $(shell git ls-files)
	sudo singularity build planner.img ./Singularity

test: planner.img
	sudo ./singularity-test.sh

clean:
	sudo rm -rf *.img rundir