
planner.img: Singularity
	sudo singularity build planner.img ./Singularity

test: planner.img
	sudo ./singularity-test.sh

clean:
	sudo rm -rf *.img rundir
