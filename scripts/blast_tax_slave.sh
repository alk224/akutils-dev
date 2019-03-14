#!/usr/bin/env bash
#
#  blast_tax_slave.sh - assign taxonomy with BLAST in QIIME
#
#  Version 1.0.0 (November, 27, 2015)
#
#  Copyright (c) 2015-- Lela Andrews
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
set -e

## Set variables
	scriptdir="$( cd "$( dirname "$0" )" && pwd )"
	repodir=`dirname $scriptdir`
	workdir=$(pwd)
	stdout="$1"
	stderr="$2"
	log="$3"
	cores="$4"
	taxmethod="$5"
	taxdir="$6"
	otupickdir="$7"
	refs="$8"
	tax="$9"
	repsetcount="${10}"
	blastevalue="${11}"

	bold=$(tput bold)
	normal=$(tput sgr0)
	underline=$(tput smul)
	res1=$(date +%s.%N)

	randcode=`cat /dev/urandom |tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1` 2>/dev/null
	tempdir="$repodir/temp/"

## Log and run command
	echo "Assigning taxonomy.
Input sequences: ${bold}$repsetcount${normal}
Method: ${bold}$taxmethod${normal} on ${bold}$cores${normal} cores.
	"
	echo "Assigning taxonomy ($taxmethod):
Input sequences: $repsetcount" >> $log
	date "+%a %b %d %I:%M %p %Z %Y" >> $log
	echo "
	parallel_assign_taxonomy_blast.py -i $otupickdir/merged_rep_set.fna -o $taxdir -r $refs -t $tax -O $cores -e $blastevalue
	" >> $log
	parallel_assign_taxonomy_blast.py -i $otupickdir/merged_rep_set.fna -o $taxdir -r $refs -t $tax -O $cores -e $blastevalue 1>$stdout 2>$stderr
	bash $scriptdir/log_slave.sh $stdout $stderr $log
	wait

## Add OTUIDs to "no blast hit" sequences, saving original assignments file
	cp $taxdir/merged_rep_set_tax_assignments.txt $taxdir/initial_merged_rep_set_tax_assignments.txt
		grep "No blast hit" $taxdir/initial_merged_rep_set_tax_assignments.txt | cut -f1 > $tempdir/${randcode}_taxids
			for randtaxid in `cat $tempdir/${randcode}_taxids`; do
				sed -i -e "s@$randtaxid\tNo blast hit@$randtaxid\tk__unknown;p__unknown;c__unknown;o__unknown;f__unknown;g__unknown;s__$randtaxid@" $taxdir/merged_rep_set_tax_assignments.txt # > $taxdir/merged_rep_set_tax_assignments.txt
			done
	wait
	rm $tempdir/${randcode}_taxids

	res2=$(date +%s.%N)
	dt=$(echo "$res2 - $res1" | bc)
	dd=$(echo "$dt/86400" | bc)
	dt2=$(echo "$dt-86400*$dd" | bc)
	dh=$(echo "$dt2/3600" | bc)
	dt3=$(echo "$dt2-3600*$dh" | bc)
	dm=$(echo "$dt3/60" | bc)
	ds=$(echo "$dt3-60*$dm" | bc)

tax_runtime=`printf "$taxmethod taxonomy assignment runtime: %d days %02d hours %02d minutes %02.1f seconds\n" $dd $dh $dm $ds`
echo "$tax_runtime

	" >> $log

exit 0
