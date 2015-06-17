#!/bin/bash
# Plot FK analysis.

usage() {
	cat <<-END >&2
	Usage: $(basename $0) (options) (stack_fk options)
	Plot an array response using stack_fk.  Command line options are
	passed to the program, but do not use -o, as this is reserved
	for the plotting script.
	
	Options:
	   -annot [name] [slow] [baz] : Add an annotation at slowness slow
	                  and backazimuth baz.  _s in name will be replaced by spaces
	                  in plotting.
	   -phase [phase1(,phase2)]   : Plot phases using the event-array geography.
	                  Quote the list and add "-mod [model]" to change model.
	
	Usage for stack_fk
	------------------
	$(stack_fk 2>&1)
	END
	exit 1
}

slow_baz2xy() {
	# Return the ux,uy coordinates for a given slowness (s/deg) and backazimuth
	# Usage: slow_baz2xy slowness backazimuth
	[ $# -ne 2 ] && { echo "Error with slow_baz2xy">&2; return 1; }
	echo "$1" "$2" | awk 'BEGIN{rad=atan2(1,1)/45} {print $1*sin(rad*$2), $1*cos(rad*$2)}'
}

plot_cross() {
	# Plot a cross at a given slowness, backazimuth location
	# Usage: plot_cross slowness backazimuth
	local xy
	[ $# -ne 2 ] && { echo "Error with plot_cross">&2; return 1; }
	xy="$(slow_baz2xy "$1" "$2")"
	echo $xy | psxy -J -R -S+0.5c -W2.5p,white -O -K >> "$FIG"
	echo $xy | psxy -J -R -S+0.45c -W1p,black -O -K >> "$FIG"
}

plot_annot_cross() {
	# Plot an annotated cross at a given slowness, backazimuth location
	# Usage: plot_annot_cross slowness backazimuth "label"
	local xy
	[ $# -ne 3 ] && { echo "Error with plot_annot_cross">&2; return 1; }
	plot_cross "$1" "$2"
	xy="$(slow_baz2xy "$1" "$2")"
	echo $xy 10 0 0 BL "$3" | pstext -J -R -D0.2c/0.2c -O -K >> "$FIG"
}

# Process arguments
while [ "$1" ]; do
	case "$1" in
		# Arguments the script knows about
		-phase) phases="$2"; shift 2;;
		-annot) name_list=("${name_list[@]}" "$2")
		        slow_list=("${slow_list[@]}" "$3")
		        baz_list=("${baz_list[@]}" "$4"); shift 4;;
		# Arguments passed to stack_fk are anything we don't know about
		*) break;;
	esac
done

# Check we're not trying to use to -o option
for arg in "$@"; do
	[ "$arg" = "-o" ] && { echo "Do not use option '-o' with plotting script"; usage; }
done

# Make temporary files
CPT=$(mktemp /tmp/plot_fk.sh.cptXXXXXX)
FIG=$(mktemp /tmp/plot_fk.sh.psXXXXXX)
GRD=$(mktemp /tmp/plot_fk.sh.grdXXXXXX)
trap 'rm -f "$CPT" "$FIG" "$GRD"' EXIT

# Plotting defaults
ls=2

# Create vespagram, passing options.  Anything read from stdin will be passed in
stack_fk -o "$GRD" "$@" || { echo "Error running stack_fk" >&2; exit 1; }

# Get info from grid file
read smin smax ds <<< $(grdinfo "$GRD" | awk '/x_min/{print $3,$5,$7}')
makecpt -Z -Chaxby -I -T0/1/0.05 > "$CPT" 2>/dev/null

# Plot power
grdimage "$GRD" -JX8c/8c -R$smin/$smax/$smin/$smax -C"$CPT" -P -K \
	-Ba$ls":@%2%u@-x@-@%% / s/deg:"/a$ls":@%2%u@-y@-@%% / s/deg:"":.Beam power:"nSeW > "$FIG" &&

# Add phase arrivals using taup if available
if [ "$phases" ]; then
	command -v taup_time >/dev/null 2>&1 ||
		{ echo "Cannot find taup_time; no phases will be plotted"; break; }
	read gcarc baz evdp <<< $(grdinfo "$GRD" |
		awk '/Command:/{print $(NF-4), $(NF-2), $NF}')
	list=$(taup_time -ph $phases -h $evdp -deg $gcarc | awk 'NR>=6')
	echo "$list" | while read gcarc_taup evdp_taup phase time slowness takeoff incident \
			distance blank pure_name; do
		plot_annot_cross $slowness $baz $phase
	done
fi

# Add annotations if any
for ((i=0; i<${#name_list[@]}; i++)); do
	plot_annot_cross "${slow_list[i]}" "${baz_list[i]}" "${name_list[i]}"
done

# Plot circles for slowness and lines for azimuth
awk -v smax=$smax 'BEGIN {
	pi = 4*atan2(1,1)
	for (r=2; r<=smax*sqrt(2); r+=2) {
		print ">"
		for (theta=0; theta<=2*pi; theta+=pi/180) print r*sin(theta), r*cos(theta)
	}
	for (theta=0; theta<2*pi; theta+=pi/6) {
		print ">"
		for (r=0; r<=100; r+=100) print r*sin(theta), r*cos(theta)
	}
	}' | psxy -J -R -m -W0.5p,- -O >> "$FIG"
gv "$FIG"
