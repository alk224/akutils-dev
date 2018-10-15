#!/usr/bin/env bash
#
#  PhiX_filtering_workflow.sh - Remove PhiX contamination from MiSeq data
#
#  Version 1.1.0 (June 16, 2015)
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
set -e

## Define variables.
	scriptdir="$( cd "$( dirname "$0" )" && pwd )"
	repodir=`dirname $scriptdir`
	workdir=$(pwd)
	stdout="$1"
	stderr="$2"
	randcode="$3"
	config="$4"
	outdir="$5"
	mapfile="$6"
	index="$7"
	read1="$8"
	read2="$9"

	bold=$(tput bold)
	normal=$(tput sgr0)
	underline=$(tput smul)

## Define filter mode based on number of supplied inputs
	if [[ "$#" == 8 ]]; then
	mode=(single)
	elif [[ "$#" == 9 ]]; then
	mode=(paired)
	fi

## Display usage if incorrect number of arguments supplied
	if [[ "$#" -ne 8 ]] && [[ "$#" -ne 9 ]]; then
		cat $repodir/docs/phix_filtering.usage
		exit 0
	fi

## Check to see if requested output directory exists
	if [[ -d $outdir ]]; then
		dirtest=$([ "$(ls -A $outdir)" ] && echo "Not Empty" || echo "Empty")
		echo "
Output directory already exists ($outdir).  Delete any contents prior to
beginning workflow or it will exit.
		"
		if [[ "$dirtest" == "Not Empty" ]]; then
		echo "
Output directory not empty.
Exiting.
		"
		exit 1
		fi
	else
		mkdir $outdir
	fi

## Define log file
	date0=`date +%Y%m%d_%I%M%p`
	log=($outdir/log_phix_filtering_$date0.txt)

##Read in variables from config file
	refs=(`grep "Reference" $config | grep -v "#" | cut -f 2`)
	tax=(`grep "Taxonomy" $config | grep -v "#" | cut -f 2`)
	tree=(`grep "Tree" $config | grep -v "#" | cut -f 2`)
	chimera_refs=(`grep "Chimeras" $config | grep -v "#" | cut -f 2`)
	seqs=($outdir/split_libraries/seqs_chimera_filtered.fna)
	alignment_template=(`grep "Alignment_template" $config | grep -v "#" | cut -f 2`)
	alignment_lanemask=(`grep "Alignment_lanemask" $config | grep -v "#" | cut -f 2`)
	revcomp=(`grep "RC_seqs" $config | grep -v "#" | cut -f 2`)
	seqs=($outdir/split_libraries/seqs.fna)
	CPU_cores=(`grep "CPU_cores" $config | grep -v "#" | cut -f 2`)
	itsx_threads=($CPU_cores)
	itsx_options=(`grep "ITSx_options" $config | grep -v "#" | cut -f 2`)
	slqual=(`grep "Split_libraries_qvalue" $config | grep -v "#" | cut -f 2`)
	chimera_threads=($CPU_cores)
	otupicking_threads=($CPU_cores)
	taxassignment_threads=($CPU_cores)
	alignseqs_threads=($CPU_cores)
	min_overlap=(`grep "Min_overlap" $config | grep -v "#" | cut -f 2`)
	max_mismatch=(`grep "Max_mismatch" $config | grep -v "#" | cut -f 2`)
	mcf_threads=($CPU_cores)
	phix_index=($repodir/akutils_resources/PhiX/phix-k11-s1)
	smalt_threads=($CPU_cores)
	multx_errors=(`grep "Multx_errors" $config | grep -v "#" | cut -f 2`)
	rdp_confidence=(`grep "RDP_confidence" $config | grep -v "#" | cut -f 2`)
	rdp_max_memory=(`grep "RDP_max_memory" $config | grep -v "#" | cut -f 2`)

## Remove file extension if necessary from supplied smalt index for smalt command and get directory
	smaltbase=`basename "$phix_index" | cut -d. -f1`
	smaltdir=`dirname $phix_index`

## Log workflow start
	if [[ `echo $mode` == "single" ]]; then
	echo "
PhiX filtering workflow beginning in single read mode."
	echo "PhiX filtering workflow beginning in single read mode." >> $log
	
	elif [[ `echo $mode` == "paired" ]]; then
	echo "
PhiX filtering workflow beginning in paired read mode."
	echo "PhiX filtering workflow beginning in paired read mode." >> $log
	fi
	date "+%a %b %d %I:%M %p %Z %Y" >> $log
	res1=$(date +%s.%N)

## Remove any blank lines from map file (will break fastq-multx)
	sed -i '/^$/d' $mapfile

## Make output directory for fastq-multx step
	mkdir $outdir/fastq-multx_output

## Extract barcodes information from mapping file
	grep -v "#" $mapfile | cut -f 1-3 > $outdir/fastq-multx_output/barcodes.fil
	barcodes=($outdir/fastq-multx_output/barcodes.fil)

## Fastq-multx command:
	echo "
Demultiplexing sample data with fastq-multx.  Allowing ${bold}${multx_errors}${normal} indexing
errors.

Mapping file: $mapfile"
	echo "
Demultiplexing data (fastq-multx):" >> $log
	date "+%a %b %d %I:%M %p %Z %Y" >> $log

	if [[ `echo $mode` == "single" ]]; then
	echo "	fastq-multx -m $multx_errors -x -B $barcodes $index $read1 -o $outdir/fastq-multx_output/index.%.fq -o $outdir/fastq-multx_output/read1.%.fq &>$outdir/fastq-multx_output/multx_log.txt" >> $log
	`fastq-multx -m $multx_errors -x -B $barcodes $index $read1 -o $outdir/fastq-multx_output/index.%.fq -o $outdir/fastq-multx_output/read1.%.fq &>$outdir/fastq-multx_output/multx_log.txt`
	
	elif [[ `echo $mode` == "paired" ]]; then
	echo "	fastq-multx -m $multx_errors -x -B $barcodes $index $read1 $read2 -o $outdir/fastq-multx_output/index.%.fq -o $outdir/fastq-multx_output/read1.%.fq -o $outdir/fastq-multx_output/read2.%.fq &>$outdir/fastq-multx_output/multx_log.txt" >> $log
	`fastq-multx -m $multx_errors -x -B $barcodes $index $read1 $read2 -o $outdir/fastq-multx_output/index.%.fq -o $outdir/fastq-multx_output/read1.%.fq -o $outdir/fastq-multx_output/read2.%.fq &>$outdir/fastq-multx_output/multx_log.txt`
	fi

## Remove unmatched sequences to save space (comment this out if you need to inspect them)
	echo "
Removing unmatched reads to save space."
	echo "
Removing unmatched reads:" >> $log
	date "+%a %b %d %I:%M %p %Z %Y" >> $log
	echo "	rm $outdir/fastq-multx_output/*unmatched.fq" >> $log

	rm $outdir/fastq-multx_output/*unmatched.fq

## Cat together multx results (in parallel)
	echo "
Remultiplexing demultiplexed data."
	echo "
Remultiplexing demultiplexed data:" >> $log
	date "+%a %b %d %I:%M %p %Z %Y" >> $log
	if [[ `echo $mode` == "single" ]]; then
	echo "	( cat $outdir/fastq-multx_output/index.*.fq > $outdir/fastq-multx_output/index.fastq ) &
	( cat $outdir/fastq-multx_output/read1.*.fq > $outdir/fastq-multx_output/read1.fastq ) &" >> $log
	( cat $outdir/fastq-multx_output/index.*.fq > $outdir/fastq-multx_output/index.fastq ) &
	( cat $outdir/fastq-multx_output/read1.*.fq > $outdir/fastq-multx_output/read1.fastq ) &
	elif [[ `echo $mode` == "paired" ]]; then
	echo "	( cat $outdir/fastq-multx_output/index.*.fq > $outdir/fastq-multx_output/index.fastq ) &
	( cat $outdir/fastq-multx_output/read1.*.fq > $outdir/fastq-multx_output/read1.fastq ) &
	( cat $outdir/fastq-multx_output/read2.*.fq > $outdir/fastq-multx_output/read2.fastq ) &" >> $log
	( cat $outdir/fastq-multx_output/index.*.fq > $outdir/fastq-multx_output/index.fastq ) &
	( cat $outdir/fastq-multx_output/read1.*.fq > $outdir/fastq-multx_output/read1.fastq ) &
	( cat $outdir/fastq-multx_output/read2.*.fq > $outdir/fastq-multx_output/read2.fastq ) &
	fi
	wait

## Define demultiplexed/remultiplexed read files
	idx=$outdir/fastq-multx_output/index.fastq
	rd1=$outdir/fastq-multx_output/read1.fastq
	if [[ `echo $mode` == "paired" ]]; then
	rd2=$outdir/fastq-multx_output/read2.fastq
	fi

## Remove demultiplexed components of read files (comment out if you need them, but they take up a lot of space)
	echo "
Removing redundant sequence files to save space."
	echo "
Removing extra files:" >> $log
	date "+%a %b %d %I:%M %p %Z %Y" >> $log
	echo "	rm $outdir/fastq-multx_output/*.fq" >> $log

	rm $outdir/fastq-multx_output/*.fq

## Smalt command to identify phix reads
	echo "
Smalt search of demultiplexed data."
	echo "
Smalt search of demultiplexed data:" >> $log
	date "+%a %b %d %I:%M %p %Z %Y" >> $log
	mkdir $outdir/smalt_output
	if [[ `echo $mode` == "single" ]]; then
	echo "	smalt map -n $smalt_threads -O -f sam:nohead -o $outdir/smalt_output/phix.mapped.sam $smaltdir/$smaltbase $rd1" >> $log
	`smalt map -n $smalt_threads -O -f sam:nohead -o $outdir/smalt_output/phix.mapped.sam $smaltdir/$smaltbase $rd1 &>>$log`
	elif [[ `echo $mode` == "paired" ]]; then
	echo "	smalt map -n $smalt_threads -O -f sam:nohead -o $outdir/smalt_output/phix.mapped.sam $smaltdir/$smaltbase $rd1 $rd2" >> $log
	`smalt map -n $smalt_threads -O -f sam:nohead -o $outdir/smalt_output/phix.mapped.sam $smaltdir/$smaltbase $rd1 $rd2 &>>$log`
	fi
	wait

#use grep to identify reads that are non-phix
	if [[ `echo $mode` == "single" ]]; then
	echo "
Screening smalt search for non-phix reads."
	echo "Screening smalt search for non-phix reads." >> $log	
	elif [[ `echo $mode` == "paired" ]]; then
	echo "
Screening smalt search for non-phix read pairs."
	echo "Screening smalt search for non-phix read pairs." >> $log
	fi
	echo "
Grep search of smalt output:" >> $log
	date "+%a %b %d %I:%M %p %Z %Y" >> $log
	if [[ `echo $mode` == "single" ]]; then
	echo "	egrep \".+\s4\s\" $outdir/smalt_output/phix.mapped.sam > $outdir/smalt_output/phix.unmapped.sam" >> $log
	egrep ".+\s4\s" $outdir/smalt_output/phix.mapped.sam > $outdir/smalt_output/phix.unmapped.sam
	elif [[ `echo $mode` == "paired" ]]; then
	echo "	egrep \".+\s77\s\" $outdir/smalt_output/phix.mapped.sam > $outdir/smalt_output/phix.unmapped.sam" >> $log
	egrep ".+\s77\s" $outdir/smalt_output/phix.mapped.sam > $outdir/smalt_output/phix.unmapped.sam
	fi
	wait

## Use filter_fasta.py to filter contaminating sequences out prior to joining
	echo "
Filtering phix reads from sample data."
	echo "
Filter phix reads with filter_fasta.py:" >> $log
	date "+%a %b %d %I:%M %p %Z %Y" >> $log
	if [[ `echo $mode` == "single" ]]; then
	echo "	( filter_fasta.py -f $outdir/fastq-multx_output/index.fastq -o $outdir/index.phixfiltered.fastq -s $outdir/smalt_output/phix.unmapped.sam ) &
	( filter_fasta.py -f $outdir/fastq-multx_output/read1.fastq -o $outdir/read1.phixfiltered.fastq -s $outdir/smalt_output/phix.unmapped.sam ) &" >> $log
	( filter_fasta.py -f $outdir/fastq-multx_output/index.fastq -o $outdir/index.phixfiltered.fastq -s $outdir/smalt_output/phix.unmapped.sam ) &
	( filter_fasta.py -f $outdir/fastq-multx_output/read1.fastq -o $outdir/read1.phixfiltered.fastq -s $outdir/smalt_output/phix.unmapped.sam ) &
	elif [[ `echo $mode` == "paired" ]]; then
	echo "	( filter_fasta.py -f $outdir/fastq-multx_output/index.fastq -o $outdir/index.phixfiltered.fastq -s $outdir/smalt_output/phix.unmapped.sam ) &
	( filter_fasta.py -f $outdir/fastq-multx_output/read1.fastq -o $outdir/read1.phixfiltered.fastq -s $outdir/smalt_output/phix.unmapped.sam ) &
	( filter_fasta.py -f $outdir/fastq-multx_output/read2.fastq -o $outdir/read2.phixfiltered.fastq -s $outdir/smalt_output/phix.unmapped.sam ) &" >> $log
	( filter_fasta.py -f $outdir/fastq-multx_output/index.fastq -o $outdir/index.phixfiltered.fastq -s $outdir/smalt_output/phix.unmapped.sam ) &
	( filter_fasta.py -f $outdir/fastq-multx_output/read1.fastq -o $outdir/read1.phixfiltered.fastq -s $outdir/smalt_output/phix.unmapped.sam ) &
	( filter_fasta.py -f $outdir/fastq-multx_output/read2.fastq -o $outdir/read2.phixfiltered.fastq -s $outdir/smalt_output/phix.unmapped.sam ) &
	fi
	wait

## Arithmetic and variable definitions to report PhiX contamintaion levels
	if [[ `echo $mode` == "single" ]]; then
	totalseqs=$(cat $outdir/smalt_output/phix.mapped.sam | wc -l)
	nonphixseqs=$(cat $outdir/smalt_output/phix.unmapped.sam | wc -l)
	phixseqs=$(($totalseqs-$nonphixseqs))
	nonphix100seqs=$(($nonphixseqs*100))
	datapercent=$(($nonphix100seqs/$totalseqs))
	contampercent=$((100-$datapercent))
	quotient=($phixseqs/$totalseqs)
	decimal=$(echo "scale=10; ${quotient}" | bc)
	elif [[ `echo $mode` == "paired" ]]; then
	totalseqs1=$(cat $outdir/smalt_output/phix.mapped.sam | wc -l)
	nonphixseqs=$(cat $outdir/smalt_output/phix.unmapped.sam | wc -l)
	totalseqs=$(($totalseqs1/2))
	phixseqs=$(($totalseqs-$nonphixseqs))
	nonphix100seqs=$(($nonphixseqs*100))
	datapercent=$(($nonphix100seqs/$totalseqs))
	contampercent=$((100-$datapercent))
	quotient=($phixseqs/$totalseqs)
	decimal=$(echo "scale=10; ${quotient}" | bc)
	fi

## Log results of PhiX filtering
	if [[ `echo $mode` == "single" ]]; then
	echo "
Processed ${bold}${totalseqs}${normal} single reads.
${bold}${phixseqs}${normal} reads contained phix sequence.
Contamination level is approximately ${bold}${contampercent}${normal} percent.
Contamination level (decimal value): ${bold}${decimal}${normal}"

	echo "
Processed $totalseqs single reads.
$phixseqs reads contained PhiX174 sequence.
Contamination level is approximately $contampercent percent.
Contamination level (decimal value): $decimal" >> $log

	elif [[ `echo $mode` == "paired" ]]; then
	echo "
Processed $totalseqs read pairs.
$phixseqs read pairs contained phix sequence.
Contamination level is approximately $contampercent percent.
Contamination level (decimal value): $decimal"

	echo "
Processed $totalseqs read pairs.
$phixseqs read pairs contained PhiX174 sequence.
Contamination level is approximately $contampercent percent.
Contamination level (decimal value): $decimal" >> $log
	fi

## Remove excess files
	rm -r $outdir/smalt_output
	rm $outdir/fastq-multx_output/*.fastq

## Log script completion
res2=$(date +%s.%N)
dt=$(echo "$res2 - $res1" | bc)
dd=$(echo "$dt/86400" | bc)
dt2=$(echo "$dt-86400*$dd" | bc)
dh=$(echo "$dt2/3600" | bc)
dt3=$(echo "$dt2-3600*$dh" | bc)
dm=$(echo "$dt3/60" | bc)
ds=$(echo "$dt3-60*$dm" | bc)
runtime=`printf "Total runtime: %d days %02d hours %02d minutes %02.1f seconds\n" $dd $dh $dm $ds`
echo "
Workflow steps completed.  Hooray!
$runtime
"
echo "
---

All workflow steps completed.  Hooray!" >> $log
date "+%a %b %d %I:%M %p %Z %Y" >> $log
echo "
$runtime 
" >> $log

exit 0
