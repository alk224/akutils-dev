#!/usr/bin/env bash
#
#  phyloseq_ordinations.sh - generate ordination plots through phyloseq
#
#  Version 1.0.0 (December 26, 2015)
#
#  Copyright (c) 2014-- Lela Andrews
#
#  This software is provided 'as-is', without any express or implied
#  warranty. In no event will the authors be held liable for any damages
#  arising from the use of this software.
#
#  Permission is granted to anyone to use this software for any purpose,
#  including commercial applications, and to alter it and redistribute it
#  freely, subject to the following restrictions:
#
#  1. The origin of this software must not be misrepresented; you must not
#     claim that you wrote the original software. If you use this software
#     in a product, an acknowledgment in the product documentation would be
#     appreciated but is not required.
#  2. Altered source versions must be plainly marked as such, and must not be
#     misrepresented as being the original software.
#  3. This notice may not be removed or altered from any source distribution.
#
## Trap function on exit.
function finish {
if [[ -f $jsontemp ]]; then
	rm $jsontemp
fi

}
trap finish EXIT

## Define variables.
	scriptdir="$( cd "$( dirname "$0" )" && pwd )"
	repodir=$(dirname $scriptdir)
	workdir=$(pwd)
	tempdir="$repodir/temp"
	randcode=`cat /dev/urandom |tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1` 2>/dev/null

	input="$1"
	map="$2"
	factor="$3"
	tree="$4"

	date0=$(date +%Y%m%d_%I%M%p)
	res0=$(date +%s.%N)

	bold=$(tput bold)
	normal=$(tput sgr0)
	underline=$(tput smul)

## Define temp files
	jsontemp="$tempdir/${randcode}_json.biom"

## If -h or --help supplied, display help
	if [[ "$1" == "-h" || "$1" == "--help" ]]; then
		less $repodir/docs/phyloseq_ordinations.help
		exit 0
	fi

## If incorrect number of inputs supplied display usage
	if [[ "$#" -ne 4 ]]; then
		cat $repodir/docs/phyloseq_ordinations.usage
		exit 0
	fi

## Test if input is properly formatted
	hdftest=$(grep "HDF" $input)
	if [[ ! -z "$hdftest" ]]; then
		## convert biom for processing
		echo "Converting input table (HDF5 format) to JSON for processing."
		biom convert -i $input -o $jsontemp --to-json
		wait
		table="$jsontemp"
		else
		table="$input"
	fi
	wait

## Execute R slave to generate network
	echo "Generating phylogenetic tree plot."
	Rscript $scriptdir/phyloseq_ordinations.r $table $map $factor &>/dev/null
	wait
	sleep 1
	if [[ -f "${factor}_tree.pdf" ]]; then
	echo "Success!

Output file: ${factor}_tree.pdf
	"
	else
	echo "
There seems to have been a problem.  Check your inputs and try again.
	"
	fi
exit 0
