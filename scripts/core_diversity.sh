#!/usr/bin/env bash
#
#  core_diversity.sh - Core diversity analysis through QIIME for OTU table analysis
#
#  Version 2.0 (December 16, 2015)
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
if [[ -f $cdivtemp ]]; then
	rm $cdivtemp
fi
if [[ -f $tablelist ]]; then
	rm $tablelist
fi
if [[ -f $catlist ]]; then
	rm $catlist
fi
if [[ -f $insamples ]]; then
	rm $insamples
fi
if [[ -f $raresamples ]]; then
	rm $raresamples
fi
if [[ -f $alphatemp ]]; then
	rm $alphatemp
fi
if [[ -f $destemp0 ]]; then
	rm $destemp0
fi
if [[ -f $destemp1 ]]; then
	rm $destemp1
fi
if [[ -f $destemp2 ]]; then
	rm $destemp2
fi
if [[ -f $destemp3 ]]; then
	rm $destemp3
fi
if [[ -f $destemp3a ]]; then
	rm $destemp3a
fi
if [[ -f $destemp4 ]]; then
	rm $destemp4
fi
if [[ -f $destemp5 ]]; then
	rm $destemp5
fi
if [[ -f $destemp6 ]]; then
	rm $destemp6
fi
if [[ -f $taxtemp0 ]]; then
	rm $taxtemp0
fi
if [[ -f $csstemp0 ]]; then
	rm $csstemp0
fi
if [[ -f $csstemp1 ]]; then
	rm $csstemp1
fi
if [[ -f $taxtemp00 ]]; then
	rm $taxtemp00
fi
if [[ -f $csstemp2 ]]; then
	rm $csstemp2
fi
if [[ -f $csstemp3 ]]; then
	rm $csstemp3
fi
if [[ -f $csstemp3a ]]; then
	rm $csstemp3a
fi
if [[ -f $csstemp4 ]]; then
	rm $csstemp4
fi
if [[ -f $csstemp5 ]]; then
	rm $csstemp5
fi
if [[ -f $csstemp6 ]]; then
	rm $csstemp6
fi
if [[ -f $filtertable0 ]]; then
	rm $filtertable0
fi
}
trap finish EXIT

## Define variables.
	scriptdir="$( cd "$( dirname "$0" )" && pwd )"
	repodir=$(dirname $scriptdir)
	workdir=$(pwd)
	tempdir="$repodir/temp"
	stdout="$1"
	stderr="$2"
	randcode="$3"
	config="$4"
	input="$5"
	inmap="$6"
	cats="$7"
	cores="$8"
	threads=$(($cores+1))

	date0=$(date +%Y%m%d_%I%M%p)
	res0=$(date +%s.%N)

	bold=$(tput bold)
	normal=$(tput sgr0)
	underline=$(tput smul)

## Define temp files
	cdivtemp="$tempdir/${randcode}_cdiv.temp"
	tablelist="$tempdir/${randcode}_cdiv_tablelist.temp"
	catlist="$tempdir/${randcode}_cdiv_categories.temp"
	alphatemp="$tempdir/${randcode}_alphametrics.temp"

## If incorrect number of arguments supplied, display usage 
	if [[ "$#" -ne 8 ]]; then 
	cat $repodir/docs/core_diversity.usage
		exit 1
	fi

## Read in variables from config file
	tree=(`grep "Tree" $config | grep -v "#" | cut -f 2`)
	adepth=(`grep "Rarefaction_depth" $config | grep -v "#" | cut -f 2`)
	threads=$(($cores+1))

## Set workflow mode (table, directory, prefix, ALL) and send list of tables to temp file
	if [[ -f "$input" && "$input" == *.biom ]]; then
	mode="table"
	echo "$input" > $tablelist
	fi
	if [[ "$input" == "ALL" ]]; then
	mode="ALL"
	find . -mindepth 3 -maxdepth 3 -name "*.biom" 2>/dev/null | grep -v "_CSS.biom" | grep -v "_DESeq2.biom" > $tablelist
	fi
	prefixtest=$(find . -mindepth 3 -maxdepth 3 -name "$input.biom" 2>/dev/null | grep -v "_CSS.biom" | grep -v "_DESeq2.biom" | wc -l)
	if [[ "$prefixtest" -ge 1 ]]; then
	mode="prefix"
	find . -mindepth 3 -maxdepth 3 -name "$input.biom" 2>/dev/null | grep -v "_CSS.biom" | grep -v "_DESeq2.biom" > $tablelist
	fi
	if [[ -d "$input" ]]; then
	mode="directory"
	find $input -name "*.biom" 2>/dev/null | grep -v "_CSS.biom" | grep -v "_DESeq2.biom" > $tablelist
	fi

	## Exit if above tests failed to add any files to tablelist
	if [[ ! -f $tablelist ]]; then
	echo "Failed to locate any tables to process with supplied input.
You supplied: $input

Exiting.
	"
	exit 1
	fi

	res0=$(date +%s.%N)
	tablecount=$(cat $tablelist | wc -l)

## Make categories temp file
	bash $scriptdir/parse_cats.sh $stdout $stderr $log $inmap $cats $catlist $randcode $tempdir

################################################################################
## Start of for loop to process each table in the master list sequentially
################################################################################

for table in `cat $tablelist`; do

		## Define initial variables
		workdir=$(pwd)
		inputdir=$(dirname $table)
		inputdirup1=$(dirname $inputdir)
		inputbase=$(basename $table .biom)
		mapbase=$(basename $inmap)

		## Summarize any tables in input directory
		biom-summarize_folder.sh $inputdir &>/dev/null
		wait

		## Determine rarefaction depth
		if [[ $adepth =~ ^[0-9]+$ ]]; then
		depth=($adepth)
		else
		depth=`awk '/Counts\/sample detail:/ {for(i=1; i<=1; i++) {getline; print $NF}}' $inputdir/$inputbase.summary | awk -F. '{print $1}'`
		fi

		## Define remaining variables, make output directory if necessary
		## and move table there for normalizing, rarefaction, and filtering
		outdir="$inputdir/core_diversity/${inputbase}_depth${depth}"
		tabledir="$outdir/OTU_tables"
		if [[ ! -d $outdir ]]; then
			mkdir -p $outdir
		fi
		if [[ ! -d $tabledir ]]; then
			mkdir -p $tabledir
		fi
		## Remove any OTUs from input which are all zero
		if [[ ! -f $tabledir/$inputbase.biom ]]; then
			filter_otus_from_otu_table.py -i $table -o $tabledir/$inputbase.biom -n 1
		fi
		if [[ ! -f $tabledir/input_mapping_file.txt ]]; then
			cp $inmap $tabledir/input_mapping_file.txt
		fi
		intable="$tabledir/$inputbase.biom"
		insummary="$tabledir/$inputbase.summary"
		mapfile="$tabledir/input_mapping_file.txt"
		mapfileabs=$(readlink -m $mapfile)

		## Find log file or set new one. 
		rm log_core_diversity*~ 2>/dev/null
		logcount=$(ls $outdir/log_core_diversity* 2>/dev/null | head -1 | wc -l)
		if [[ "$logcount" -eq 1 ]]; then
		log0=`ls $outdir/log_core_diversity*.txt | head -1`
		log=$(readlink -m $log0)
		elif [[ "$logcount" -eq 0 ]]; then
		log0="$outdir/log_core_diversity_$date0.txt"
		log=$(readlink -m $log0)
		fi
		echo "
${bold}akutils core_diversity workflow beginning.${normal}"
		echo "

++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

akutils core_diversity workflow beginning." >> $log
		date >> $log
echo "
********************************************************************************

INITIAL TABLE PROCESSING STARTS HERE

********************************************************************************
" >> $log

		## List validated categories to screen and log
	echo "
Validated input categories:"
	echo "
Validated input categories:" >> $log
for line in `cat $catlist`; do
	echo $line
	echo $line >> $log
done

		## Find phylogenetic tree or set mode nonphylogenetic
	if [[ -f "$tree" ]]; then
	treebase=$(basename $tree)
	phylogenetic="YES"
	metrics="bray_curtis,chord,hellinger,kulczynski,unweighted_unifrac,weighted_unifrac"
	alphametrics="PD_whole_tree,chao1,observed_species,shannon"
	elif [[ "$tree" == "AUTO" ]]; then

		if [[ -f $inputdirup1/pynast_alignment/fasttree_phylogeny.tre ]]; then
		tree="$inputdirup1/pynast_alignment/fasttree_phylogeny.tre"
		treebase=$(basename $tree)
		phylogenetic="YES"
		metrics="bray_curtis,chord,hellinger,kulczynski,unweighted_unifrac,weighted_unifrac"
		alphametrics="PD_whole_tree,chao1,observed_species,shannon"
		fi
		if [[ -f $inputdirup1/mafft_alignment/fasttree_phylogeny.tre ]]; then
		tree="$inputdirup1/mafft_alignment/fasttree_phylogeny.tre"
		treebase=$(basename $tree)
		phylogenetic="YES"
		metrics="bray_curtis,chord,hellinger,kulczynski,unweighted_unifrac,weighted_unifrac"
		alphametrics="PD_whole_tree,chao1,observed_species,shannon"
		fi
	fi

	if [[ -z $phylogenetic ]]; then
	phylogenetic="NO"
	metrics="bray_curtis,chord,hellinger,kulczynski"
	alphametrics="chao1,observed_species,shannon"
	fi

		## Make alpha metrics temp file
		echo > $alphatemp
		IN=$alphametrics
		OIFS=$IFS
		IFS=','
		arr=$IN
		for x in $arr; do
			echo $x >> $alphatemp
		done
		IFS=$OIFS
		sed -i '/^\s*$/d' $alphatemp

		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

		## Summarize input table
		biom-summarize_folder.sh $tabledir &>/dev/null

		## Refresh html output
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

		## Rarefy input table according to established depth
		raretable="$tabledir/rarefied_table.biom"
		raresummary="$tabledir/rarefied_table.summary"
		if [[ ! -f $raretable ]]; then
		echo "
Input table: $table
Rarefying input table according to config file ($adepth).
${bold}Rarefaction depth: $depth${normal}"

		echo "
Input table: $table
Rarefying input table according to config file ($adepth).
Rarefaction depth: $depth" >> $log

		echo "
Single rarefaction command:
	single_rarefaction.py -i $intable -o $raretable -d $depth" >> $log
		single_rarefaction.py -i $intable -o $raretable -d $depth 1> $stdout 2> $stderr
		wait
		bash $scriptdir/log_slave.sh $stdout $stderr $log
		fi

		biom-summarize_folder.sh $tabledir &>/dev/null
		rarebase=$(basename $raretable .biom)

		## Refresh html output
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

		## Filter any samples removed by rarefying from the original input table
		inlines0=$(cat $insummary | wc -l)
		inlines=$(($inlines0-14))
		rarelines0=$(cat $raresummary | wc -l)
		rarelines=$(($rarelines0-14))

		insamples="$tempdir/${randcode}_insamples.temp"
		raresamples="$tempdir/${randcode}_raresamples.temp"
		cat $insummary | tail -$inlines | cut -d":" -f1 > $insamples
		cat $raresummary | tail -$rarelines | cut -d":" -f1 > $raresamples
		insamplecount=$(cat $insamples | wc -l)
		raresamplecount=$(cat $raresamples | wc -l)
		diffcount=$(($insamplecount-$raresamplecount))

		filtertable0="$tempdir/${randcode}_sample_filtered_table0.biom"
		filtertable="$tabledir/sample_filtered_table.biom"
		if [[ ! -f $filtertable ]]; then
		filtering="yes"
		echo "
Filtering any samples removed during rarefaction."
		echo "
Filtering any samples removed during rarefaction:
	filter_samples_from_otu_table.py -i $intable -o $filtertable0 --sample_id_fp $raresamples" >> $log
		filter_samples_from_otu_table.py -i $intable -o $filtertable0 --sample_id_fp $raresamples 1> $stdout 2> $stderr
		bash $scriptdir/log_slave.sh $stdout $stderr $log
		else
		echo "
Sample-filtered table already present." >> $log
		fi

		## Log any sample removals
		echo "
${bold}Rarefaction removed $diffcount samples${normal} from the analysis during:"
		echo "
Rarefaction removed $diffcount samples from the analysis following rarefaction:" >> $log
		grep -vFf $raresamples $insamples
		grep -vFf $raresamples $insamples >> $log

		## Remove any zeroed OTUs
		if [[ "$filtering" == "yes" ]]; then
		echo "
Removing any OTUs randomly reduced to zero counts during rarefaction."
		echo "
Removing any OTUs randomly reduced to zero counts during rarefaction:
	filter_otus_from_otu_table.py -i $filtertable0 -o $filtertable -n 2" >> $log
		filter_otus_from_otu_table.py -i $filtertable0 -o $filtertable -n 1 1> $stdout 2> $stderr
		bash $scriptdir/log_slave.sh $stdout $stderr $log
		fi

		## Normalize filtered table with CSS and DESeq2 transformations
		CSStable="$tabledir/CSS_table.biom"
		DESeq2table0="$tabledir/DESeq2_table0.biom"
		DESeq2table="$tabledir/DESeq2_table.biom"
		if [[ ! -f $CSStable ]]; then
		echo "
Normalizing sample-filtered table with CSS transformation."
		echo "
Normalizing sample-filtered table with CSS transformation:
	normalize_table.py -i $filtertable -o $CSStable -a CSS" >> $log

		## Preserve taxonomy with text manipulation to avoid mangling of certain strings
			csstemp0="$tempdir/${randcode}_temp_css0.biom"
			csstemp1="$tempdir/${randcode}_temp_css0.txt"
			taxtemp00="$tempdir/${randcode}_temp_tax00.txt"
			cp $filtertable $csstemp0 2>/dev/null
			biomtotxt.sh $csstemp0  &>/dev/null
			column0=`awk -v table="$csstemp1" '{ for(i=1;i<=NF;i++){if ($i ~ /taxonomy/) {print i}}}' $csstemp1`
			column1=`expr $column0 - 2`
			taxcol=`expr $column0 - 1`
			cat $csstemp1 2>/dev/null | cut -f${taxcol} > $taxtemp00
			if [[ ! -f $CSStable ]]; then
			normalize_table.py -i $filtertable -o $CSStable -a CSS 1> $stdout 2> $stderr || true
			bash $scriptdir/log_slave.sh $stdout $stderr $log
		## Add taxonomy back in
			csstemp2="$tempdir/${randcode}_temp_css2.biom"
			csstemp3="$tempdir/${randcode}_temp_css2.txt"
			csstemp3a="$tempdir/${randcode}_temp_css3a.txt"
			csstemp4="$tempdir/${randcode}_temp_css4.txt"
			csstemp5="$tempdir/${randcode}_temp_css4.biom"
			csstemp6="$tempdir/${randcode}_temp_css6.biom"
			cp $CSStable $csstemp2 2>/dev/null
			biomtotxt.sh $csstemp2 &>/dev/null
			cat $csstemp3 2>/dev/null | cut -f1-${column1} > $csstemp3a
			paste $csstemp3a $taxtemp00 > $csstemp4
			txttobiom.sh $csstemp4 &>/dev/null
			filter_otus_from_otu_table.py -i $csstemp5 -o $csstemp6 -n 1 &>/dev/null
			cp $csstemp6 $CSStable &>/dev/null
			fi
			if [[ ! -f "$CSStable" ]]; then
			echo "
Failed to produce valid output from CSS normalization. Skipping all associated steps."
echo "
Failed to produce valid output from CSS normalization. Skipping all associated steps." >> $log
			fi
		wait
		fi
			if [[ -f "$CSStable" ]]; then
			cssnorm="yes"
			else
			cssnorm="no"
			fi

		if [[ ! -f $DESeq2table ]]; then
		echo "
Normalizing sample-filtered table with DESeq2 transformation (converting neg values to zeros)."
		echo "
Normalizing sample-filtered table with DESeq2 transformation (converting neg values to zeros):
	normalize_table.py -i $filtertable -o $DESeq2table -a DESeq2 -z" >> $log

		## First lift taxonomy to temp file because of annoying shortcoming of DESeq2 transformation (doesn't keep taxonomy)
			destemp0="$tempdir/${randcode}_temp_des0.biom"
			destemp1="$tempdir/${randcode}_temp_des0.txt"
			taxtemp0="$tempdir/${randcode}_temp_tax0.txt"
			cp $filtertable $destemp0 2>/dev/null
			biomtotxt.sh $destemp0  &>/dev/null
			column0=`awk -v table="$destemp1" '{ for(i=1;i<=NF;i++){if ($i ~ /taxonomy/) {print i}}}' $destemp1`
			column1=`expr $column0 - 2`
			taxcol=`expr $column0 - 1`
			cat $destemp1 2>/dev/null | cut -f${taxcol} > $taxtemp0
			if [[ ! -f $DESeq2table ]]; then
			normalize_table.py -i $filtertable -o $DESeq2table -a DESeq2 -z 1> $stdout 2> $stderr || true
			bash $scriptdir/log_slave.sh $stdout $stderr $log
		## Add taxonomy back in
			destemp2="$tempdir/${randcode}_temp_des2.biom"
			destemp3="$tempdir/${randcode}_temp_des2.txt"
			destemp3a="$tempdir/${randcode}_temp_des3a.txt"
			destemp4="$tempdir/${randcode}_temp_des4.txt"
			destemp5="$tempdir/${randcode}_temp_des4.biom"
			destemp6="$tempdir/${randcode}_temp_des6.biom"
			cp $DESeq2table $destemp2 2>/dev/null
			biomtotxt.sh $destemp2 &>/dev/null
			cat $destemp3 2>/dev/null | cut -f1-${column1} > $destemp3a
			paste $destemp3a $taxtemp0 > $destemp4
			txttobiom.sh $destemp4  &>/dev/null
			filter_otus_from_otu_table.py -i $destemp5 -o $destemp6 -n 1 &>/dev/null
			cp $destemp6 $DESeq2table 2>/dev/null
			fi
			if [[ ! -f "$DESeq2table" ]]; then
			echo "
Failed to produce valid output from DESeq2 normalization. Skipping all associated steps."
echo "
Failed to produce valid output from DESeq2 normalization. Skipping all associated steps." >> $log
			fi

		wait
		fi
			if [[ -f "$DESeq2table" ]]; then
			desnorm="yes"
			else
			desnorm="no"
			fi

		## Summarize tables one last time and refresh html output
		biom-summarize_folder.sh $tabledir &>/dev/null
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

		## Sort OTU tables
		CSSsort="$outdir/OTU_tables/CSS_table_sorted.biom"
		DESeq2sort="$outdir/OTU_tables/DESeq2_table_sorted.biom"
		raresort="$outdir/OTU_tables/rarefied_table_sorted.biom"
		if [[ ! -f $CSSsort ]]; then
		sort_otu_table.py -i $CSStable -o $CSSsort 2>/dev/null
		echo "
		sort_otu_table.py -i $CSStable -o $CSSsort" >> $log
		fi
		if [[ ! -f $DESeq2sort ]]; then
		sort_otu_table.py -i $DESeq2table -o $DESeq2sort 2>/dev/null
		echo "
		sort_otu_table.py -i $DESeq2table -o $DESeq2sort" >> $log
		fi
		if [[ ! -f $raresort ]]; then
		sort_otu_table.py -i $raretable -o $raresort 2>/dev/null
		echo "
		sort_otu_table.py -i $raretable -o $raresort" >> $log
		fi

		## Relativize rarefied and CSS tables
		raresortrel="$outdir/OTU_tables/rarefied_table_sorted_relativized.biom"
		CSSsortrel="$outdir/OTU_tables/CSS_table_sorted_relativized.biom"
		DESeq2sortrel="$outdir/OTU_tables/DESeq2_table_sorted_relativized.biom"
		if [[ ! -f $raresortrel ]]; then
		relativize_otu_table.py -i $raresort >/dev/null 2>&1 || true
		echo "
		relativize_otu_table.py -i $raresort" >> $log
		fi
		if [[ ! -f $CSSsortrel ]]; then
		relativize_otu_table.py -i $CSSsort >/dev/null 2>&1 || true
		echo "
		relativize_otu_table.py -i $CSSsort" >> $log
		fi
		if [[ ! -f $DESeq2sortrel ]]; then
		relativize_otu_table.py -i $DESeq2sort >/dev/null 2>&1 || true
		echo "
		relativize_otu_table.py -i $DESeq2sort" >> $log
		fi

		# Add sample metadata to rarefied and normalized tables (both relativized and count format)
		raresortwmd="$outdir/OTU_tables/rarefied_table_sorted_with_metadata.biom"
		raresortrelwmd="$outdir/OTU_tables/rarefied_table_sorted_relativized_with_metadata.biom"
		CSSsortwmd="$outdir/OTU_tables/CSS_table_sorted_with_metadata.biom"
		CSSsortrelwmd="$outdir/OTU_tables/CSS_table_sorted_relativized_with_metadata.biom"
		DESeq2sortwmd="$outdir/OTU_tables/DESeq2_table_sorted_with_metadata.biom"
		DESeq2sortrelwmd="$outdir/OTU_tables/DESeq2_table_sorted_relativized_with_metadata.biom"
		biom add-metadata -i $raresort -o $raresortwmd --sample-metadata-fp $mapfile >/dev/null 2>&1 || true
		biom add-metadata -i $CSSsort -o $CSSsortwmd --sample-metadata-fp $mapfile >/dev/null 2>&1 || true
		biom add-metadata -i $DESeq2sort -o $DESeq2sortwmd --sample-metadata-fp $mapfile >/dev/null 2>&1 || true
		biom add-metadata -i $raresortrel -o $raresortrelwmd --sample-metadata-fp $mapfile >/dev/null 2>&1 || true
		biom add-metadata -i $CSSsortrel -o $CSSsortrelwmd --sample-metadata-fp $mapfile >/dev/null 2>&1 || true
		biom add-metadata -i $DESeq2sortrel -o $DESeq2sortrelwmd --sample-metadata-fp $mapfile >/dev/null 2>&1 || true

		## Report mode and metrics
		if [[ "$phylogenetic" == "YES" ]]; then
		echo "
Analysis will be ${bold}phylogenetic${normal}.
${bold}Alpha diversity metrics:${normal} $alphametrics
${bold}Beta diversity metrics:${normal} $metrics
${bold}Tree file:${normal} $tree"
		echo "
Analysis will be phylogenetic.
Alpha diversity metrics: $alphametrics
Beta diversity metrics: $metrics
Tree file: $tree" >> $log
		elif [[ "$phylogenetic" == "NO" ]]; then
		echo "
Analysis will be nonphylogenetic.
${bold}Alpha diversity metrics:${normal} $alphametrics
${bold}Beta diversity metrics:${normal} $metrics
${bold}Tree file:${normal} None found"
		echo "
Analysis will be nonphylogenetic.
Alpha diversity metrics: $alphametrics
Beta diversity metrics: $metrics
Tree file: None found" >> $log
		fi

		## Make .txt versions of analysis tables
		intabletxt="$outdir/OTU_tables/$inputbase.txt"
		raresorttxt="$outdir/OTU_tables/rarefied_table_sorted.txt"
		raresortreltxt="$outdir/OTU_tables/rarefied_table_sorted_relativized.txt"
		filtertabletxt="$outdir/OTU_tables/sample_filtered_table.txt"
		CCSsorttxt="$outdir/OTU_tables/CSS_table_sorted.txt"
		CSSsortreltxt="$outdir/OTU_tables/CSS_table_sorted_relativized.txt"
		DESeq2sorttxt="$outdir/OTU_tables/DESeq2_table_sorted.txt"
		DESeq2sortreltxt="$outdir/OTU_tables/DESeq2_table_sorted_relativized.txt"
#		CSSsortwmdtxt="$outdir/OTU_tables/CSS_table_sorted_with_metadata.txt"
#		raresortwmdtxt="$outdir/OTU_tables/rarefied_table_sorted_with_metadata.txt"
#		raresortrelwmdtxt="$outdir/OTU_tables/rarefied_table_sorted_relativized_with_metadata.txt"
#		CSSsortrelwmdtxt="$outdir/OTU_tables/CSS_table_sorted_relativized_with_metadata.txt"

		if [[ ! -f $CSSsorttxt ]]; then
		biomtotxt.sh $CSSsort &>/dev/null
		fi
		if [[ ! -f $raresorttxt ]]; then
		biomtotxt.sh $raresort &>/dev/null
		fi
		if [[ ! -f $intabletxt ]]; then
		biomtotxt.sh $intable &>/dev/null
		fi
		if [[ ! -f $filtertabletxt ]]; then
		biomtotxt.sh $filtertable &>/dev/null
		fi
		if [[ ! -f $raresortreltxt ]]; then
		biomtotxt.sh $raresortrel &>/dev/null
		fi
		if [[ ! -f $CSSsortreltxt ]]; then
		biomtotxt.sh $CSSsortrel &>/dev/null
		fi
		if [[ ! -f $DESeq2sorttxt ]]; then
		biomtotxt.sh $DESeq2sort &>/dev/null
		fi
		if [[ ! -f $DESeq2sortreltxt ]]; then
		biomtotxt.sh $DESeq2sortrel &>/dev/null
		fi
#		if [[ ! -f $CSSsortwmdtxt ]]; then
#		biomtotxt.sh $CSSsortwmd &>/dev/null
#		fi
#		if [[ ! -f $raresortwmdtxt ]]; then
#		biomtotxt.sh $raresortwmd &>/dev/null
#		fi
#		if [[ ! -f $raresortrelwmdtxt ]]; then
#		biomtotxt.sh $raresortrelwmd &>/dev/null
#		fi
#		if [[ ! -f $CSSsortrelwmdtxt ]]; then
#		biomtotxt.sh $CSSsortrelwmd &>/dev/null
#		fi

		## Build tree plots
		if [[ "$phylogenetic" == "YES" ]]; then
		if [[ ! -d $outdir/Phyloseq_output/Trees ]]; then
		echo "
Generating phylogenetic tree plots based on input."
			mkdir -p $outdir/Phyloseq_output/Trees 2>/dev/null
			cp $tree $outdir/Phyloseq_output/Trees/ 2>/dev/null
	#		randcode1=`cat /dev/urandom |tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1` 2>/dev/null
			bash $scriptdir/phyloseq_tree.sh $filtertable $mapfile $tree NULL phylum $outdir/Phyloseq_output/Trees/ &>/dev/null
			wait
	#			mv Phylum_tree_${randcode1}.pdf $outdir/Phyloseq_output/Trees/Phylum_tree.pdf 2>/dev/null

			for line in `cat $catlist`; do
	#		randcode1=`cat /dev/urandom |tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1` 2>/dev/null
			bash $scriptdir/phyloseq_tree.sh $filtertable $mapfile $tree $line detail $outdir/Phyloseq_output/Trees/ &>/dev/null
			wait
#				mv ${line}_detail_tree_${randcode1}.pdf $outdir/Phyloseq_output/Trees/${line}_detail_tree.pdf 2>/dev/null
			done
		fi
		fi

		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

		## Build network plots
		if [[ ! -d $outdir/Phyloseq_output/Networks ]]; then
		echo "
Generating network plots for each supplied category."
			mkdir -p $outdir/Phyloseq_output/Networks 2>/dev/null
			for line in `cat $catlist`; do
		#	randcode1=`cat /dev/urandom |tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1` 2>/dev/null
			bash $scriptdir/phyloseq_network.sh $filtertable $mapfile $line $outdir/Phyloseq_output/Networks/ &>/dev/null
			wait
#				mv ${line}_network_${randcode1}.pdf $outdir/Phyloseq_output/Networks/${line}_network.pdf 2>/dev/null
			done
		fi

		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

################################################################################
## START OF CSS NORMALIZED ANALYSIS HERE

	if [[ "$cssnorm" == "yes" ]]; then
echo "
********************************************************************************

CSS NORMALIZED TABLE PROCESSING STARTS HERE

********************************************************************************
" >> $log

	echo "
Processing CSS normalized table."
	echo "
Processing CSS normalized table." >> $log

## Produce summary plots first through phyloseq (in parallel)



## Summarize taxa (yields relative abundance tables)
	if [[ ! -d $outdir/CSS_normalized_output/beta_diversity/summarized_tables ]]; then
	echo "
Summarize taxa command:
	summarize_taxa.py -i $CSSsort -o $outdir/CSS_normalized_output/beta_diversity/summarized_tables -L 2,3,4,5,6,7" >> $log
	echo "
Summarizing taxonomy by sample and building plots."
	summarize_taxa.py -i $CSSsort -o $outdir/CSS_normalized_output/beta_diversity/summarized_tables -L 2,3,4,5,6,7 1> $stdout 2> $stderr
	bash $scriptdir/log_slave.sh $stdout $stderr $log
	
	else
	echo "
Relative abundance tables already present." >> $log
	fi
	wait

## Beta diversity
	if [[ "$phylogenetic" == "YES" ]]; then
	if [[ ! -f $outdir/CSS_normalized_output/beta_diversity/bray_curtis_dm.txt && ! -f $outdir/CSS_normalized_output/beta_diversity/chord_dm.txt && ! -f $outdir/CSS_normalized_output/beta_diversity/hellinger_dm.txt && ! -f $outdir/CSS_normalized_output/beta_diversity/kulczynski_dm.txt && ! -f $outdir/CSS_normalized_output/beta_diversity/unweighted_unifrac_dm.txt && ! -f $outdir/CSS_normalized_output/beta_diversity/weighted_unifrac_dm.txt ]]; then
	echo "
Parallel beta diversity command:
	parallel_beta_diversity.py -i $CSSsort -o $outdir/CSS_normalized_output/beta_diversity/ --metrics $metrics -T  -t $tree --jobs_to_start $cores" >> $log
	echo "
Calculating beta diversity distance matrices."
	parallel_beta_diversity.py -i $CSSsort -o $outdir/CSS_normalized_output/beta_diversity/ --metrics $metrics -T  -t $tree --jobs_to_start $cores 1> $stdout 2> $stderr
	bash $scriptdir/log_slave.sh $stdout $stderr $log
	fi
	elif [[ "$phylogenetic" == "NO" ]]; then
	if [[ ! -f $outdir/CSS_normalized_output/beta_diversity/bray_curtis_dm.txt && ! -f $outdir/CSS_normalized_output/beta_diversity/chord_dm.txt && ! -f $outdir/CSS_normalized_output/beta_diversity/hellinger_dm.txt && ! -f $outdir/CSS_normalized_output/beta_diversity/kulczynski_dm.txt ]]; then
	echo "
Parallel beta diversity command:
	parallel_beta_diversity.py -i $CSSsort -o $outdir/CSS_normalized_output/beta_diversity/ --metrics $metrics -T --jobs_to_start $cores" >> $log
	echo "
Calculating beta diversity distance matrices."
	parallel_beta_diversity.py -i $CSSsort -o $outdir/CSS_normalized_output/beta_diversity/ --metrics $metrics -T --jobs_to_start $cores 1> $stdout 2> $stderr
	bash $scriptdir/log_slave.sh $stdout $stderr $log
	fi
	else
	echo "
Beta diversity matrices already present." >> $log
	fi
	wait

## Rename output files
	if [[ ! -f $outdir/CSS_normalized_output/beta_diversity/bray_curtis_dm.txt ]]; then
	bcdm=$(ls $outdir/CSS_normalized_output/beta_diversity/bray_curtis_*.txt)
	mv $bcdm $outdir/CSS_normalized_output/beta_diversity/bray_curtis_dm.txt 2>/dev/null
	fi
	wait
	if [[ ! -f $outdir/CSS_normalized_output/beta_diversity/chord_dm.txt ]]; then
	cdm=$(ls $outdir/CSS_normalized_output/beta_diversity/chord_*.txt)
	mv $cdm $outdir/CSS_normalized_output/beta_diversity/chord_dm.txt 2>/dev/null
	fi
	wait
	if [[ ! -f $outdir/CSS_normalized_output/beta_diversity/hellinger_dm.txt ]]; then
	hdm=$(ls $outdir/CSS_normalized_output/beta_diversity/hellinger_*.txt)
	mv $hdm $outdir/CSS_normalized_output/beta_diversity/hellinger_dm.txt 2>/dev/null
	fi
	wait
	if [[ ! -f $outdir/CSS_normalized_output/beta_diversity/kulczynski_dm.txt ]]; then
	kdm=$(ls $outdir/CSS_normalized_output/beta_diversity/kulczynski_*.txt)
	mv $kdm $outdir/CSS_normalized_output/beta_diversity/kulczynski_dm.txt 2>/dev/null
	fi
	wait
	if [[ "$phylogenetic" == "YES" ]]; then
	if [[ ! -f $outdir/CSS_normalized_output/beta_diversity/unweighted_unifrac_dm.txt ]]; then
	uudm=$(ls $outdir/CSS_normalized_output/beta_diversity/unweighted_unifrac_*.txt)
	mv $uudm $outdir/CSS_normalized_output/beta_diversity/unweighted_unifrac_dm.txt 2>/dev/null
	fi
	wait
	if [[ ! -f $outdir/CSS_normalized_output/beta_diversity/weighted_unifrac_dm.txt ]]; then
	wudm=$(ls $outdir/CSS_normalized_output/beta_diversity/weighted_unifrac_*.txt)
	mv $wudm $outdir/CSS_normalized_output/beta_diversity/weighted_unifrac_dm.txt 2>/dev/null
	fi
	wait
	fi
	wait

## Principal coordinates and NMDS commands
	pcoacoordscount=`ls $outdir/CSS_normalized_output/beta_diversity/*_pc.txt 2>/dev/null | wc -l`
	nmdscoordscount=`ls $outdir/CSS_normalized_output/beta_diversity/*_nmds.txt 2>/dev/null | wc -l`
	nmdsconvertcoordscount=`ls $outdir/CSS_normalized_output/beta_diversity/*_nmds_converted.txt 2>/dev/null | wc -l`
	if [[ $pcoacoordscount == 0 && $nmdscoordscount == 0 && $nmdsconvertcoordscount == 0 ]]; then
	echo "
Principal coordinates and NMDS commands." >> $log
	echo "
Constructing PCoA and NMDS coordinate files."
	echo "Principal coordinates:" >> $log
	for dm in $outdir/CSS_normalized_output/beta_diversity/*_dm.txt; do
	dmbase=$(basename $dm _dm.txt)
	echo "	principal_coordinates.py -i $dm -o $outdir/CSS_normalized_output/beta_diversity/${dmbase}_pc.txt" >> $log
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	( principal_coordinates.py -i $dm -o $outdir/CSS_normalized_output/beta_diversity/${dmbase}_pc.txt >/dev/null 2>&1 || true ) &
	done
	wait
	echo "" >> $log

	echo "NMDS coordinates:" >> $log
	for dm in $outdir/CSS_normalized_output/beta_diversity/*_dm.txt; do
	dmbase=$(basename $dm _dm.txt)
	echo "	nmds.py -i $dm -o $outdir/CSS_normalized_output/beta_diversity/${dmbase}_nmds.txt" >> $log
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	( nmds.py -i $dm -o $outdir/CSS_normalized_output/beta_diversity/${dmbase}_nmds.txt >/dev/null 2>&1 || true ) &
	done
	wait
	echo "" >> $log

	echo "Convert NMDS coordinates:" >> $log
	for dm in $outdir/CSS_normalized_output/beta_diversity/*_dm.txt; do
	dmbase=$(basename $dm _dm.txt)
	echo "	python $scriptdir/convert_nmds_coords.py -i $outdir/CSS_normalized_output/beta_diversity/${dmbase}_nmds.txt -o $outdir/CSS_normalized_output/beta_diversity/${dmbase}_nmds_converted.txt" >> $log
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	( python $scriptdir/convert_nmds_coords.py -i $outdir/CSS_normalized_output/beta_diversity/${dmbase}_nmds.txt -o $outdir/CSS_normalized_output/beta_diversity/${dmbase}_nmds_converted.txt >/dev/null 2>&1 || true ) &
	done
	wait
	echo "" >> $log
	else
	echo "
PCoA and NMDS coordinate files already present." >> $log
	fi

## Make 3D emperor plots (PCoA)
	pcoaplotscount=`ls $outdir/CSS_normalized_output/beta_diversity/*_pcoa_plot 2>/dev/null | wc -l`
	if [[ $pcoaplotscount == 0 ]]; then
	echo "
Make emperor commands:" >> $log
	echo "
Generating 3D PCoA plots."
	echo "PCoA plots:" >> $log
	for pc in $outdir/CSS_normalized_output/beta_diversity/*_pc.txt; do
	pcbase=$(basename $pc _pc.txt)
		if [[ -d $outdir/CSS_normalized_output/beta_diversity/${pcbase}_emperor_pcoa_plot/ ]]; then
		rm -r $outdir/CSS_normalized_output/beta_diversity/${pcbase}_emperor_pcoa_plot/
		fi
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	echo "	make_emperor.py -i $pc -o $outdir/CSS_normalized_output/beta_diversity/${pcbase}_emperor_pcoa_plot/ -m $mapfile --add_unique_columns --ignore_missing_samples" >> $log
	( make_emperor.py -i $pc -o $outdir/CSS_normalized_output/beta_diversity/${pcbase}_emperor_pcoa_plot/ -m $mapfile --add_unique_columns --ignore_missing_samples >/dev/null 2>&1 || true ) &
	done
	wait
	echo "" >> $log
	else
	echo "
3D PCoA plots already present." >> $log
	fi

## Make 3D emperor plots (NMDS)
	nmdsplotscount=`ls $outdir/CSS_normalized_output/beta_diversity/*_nmds_plot 2>/dev/null | wc -l`
	if [[ $nmdsplotscount == 0 ]]; then
	echo "
Generating 3D NMDS plots."
	echo "NMDS plots:" >> $log
	for nmds in $outdir/CSS_normalized_output/beta_diversity/*_nmds_converted.txt; do
	nmdsbase=$(basename $nmds _nmds_converted.txt)
		if [[ -d $outdir/CSS_normalized_output/beta_diversity/${nmdsbase}_emperor_nmds_plot/ ]]; then
		rm -r $outdir/CSS_normalized_output/beta_diversity/${nmdsbase}_emperor_nmds_plot/
		fi
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	echo "	make_emperor.py -i $nmds -o $outdir/CSS_normalized_output/beta_diversity/${nmdsbase}_emperor_nmds_plot/ -m $mapfile --add_unique_columns --ignore_missing_samples" >> $log
	( make_emperor.py -i $nmds -o $outdir/CSS_normalized_output/beta_diversity/${nmdsbase}_emperor_nmds_plot/ -m $mapfile --add_unique_columns --ignore_missing_samples >/dev/null 2>&1 || true ) &
	done
	wait
	echo "" >> $log
	else
	echo "
3D NMDS plots already present." >> $log
	fi

	## Update HTML output
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

## Make 2D plots
	if [[ ! -d $outdir/CSS_normalized_output/beta_diversity/2D_PCoA_bdiv_plots ]]; then
	echo "
Make 2D PCoA plots commands:" >> $log
	echo "
Generating 2D PCoA plots."
	for pc in $outdir/CSS_normalized_output/beta_diversity/*_pc.txt; do
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	echo "	make_2d_plots.py -i $pc -m $mapfile -o $outdir/CSS_normalized_output/beta_diversity/2D_PCoA_bdiv_plots" >> $log
	( make_2d_plots.py -i $pc -m $mapfile -o $outdir/CSS_normalized_output/beta_diversity/2D_PCoA_bdiv_plots >/dev/null 2>&1 || true ) &
	done
	wait
	echo "" >> $log
	else
	echo "
2D plots already present." >> $log
	fi

	## Update HTML output
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

## Comparing categories statistics
if [[ ! -f $outdir/CSS_normalized_output/beta_diversity/permanova_results_collated.txt && ! -f $outdir/CSS_normalized_output/beta_diversity/permdisp_results_collated.txt && ! -f $outdir/CSS_normalized_output/beta_diversity/anosim_results_collated.txt && ! -f $outdir/CSS_normalized_output/beta_diversity/dbrda_results_collated.txt && ! -f $outdir/CSS_normalized_output/beta_diversity/adonis_results_collated.txt ]]; then
echo "
Compare categories commands:" >> $log
	echo "
Calculating one-way statsitics from distance matrices."
	if [[ ! -f $outdir/CSS_normalized_output/beta_diversity/permanova_results_collated.txt ]]; then
echo "Running PERMANOVA tests."
echo "PERMANOVA:" >> $log
	for line in `cat $catlist`; do
		for dm in $outdir/CSS_normalized_output/beta_diversity/*_dm.txt; do
		method=$(basename $dm _dm.txt)
		while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
		sleep 1
		done
		echo "	compare_categories.py --method permanova -i $dm -m $mapfile -c $line -o $outdir/CSS_normalized_output/beta_diversity/permanova_out/$line/$method/" >> $log
		( compare_categories.py --method permanova -i $dm -m $mapfile -c $line -o $outdir/CSS_normalized_output/beta_diversity/permanova_out/$line/$method/ >/dev/null 2>&1 || true ) &
		done
	done
	wait
	echo "" >> $log

	for line in `cat $catlist`; do
		for dm in $outdir/CSS_normalized_output/beta_diversity/*_dm.txt; do
		method=$(basename $dm _dm.txt)
		echo "Category: $line" >> $outdir/CSS_normalized_output/beta_diversity/permanova_results_collated.txt
		echo "Method: $method" >> $outdir/CSS_normalized_output/beta_diversity/permanova_results_collated.txt
		cat $outdir/CSS_normalized_output/beta_diversity/permanova_out/$line/$method/permanova_results.txt >> $outdir/CSS_normalized_output/beta_diversity/permanova_results_collated.txt 2>/dev/null || true
		echo "" >> $outdir/CSS_normalized_output/beta_diversity/permanova_results_collated.txt
		done
	done
	wait
	fi

	if [[ ! -f $outdir/CSS_normalized_output/beta_diversity/permdisp_results_collated.txt ]]; then
echo "Running PERMDISP tests."
echo "PERMDISP:" >> $log
	for line in `cat $catlist`; do
		for dm in $outdir/CSS_normalized_output/beta_diversity/*_dm.txt; do
		method=$(basename $dm _dm.txt)
		while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
		sleep 1
		done
		echo "	compare_categories.py --method permdisp -i $dm -m $mapfile -c $line -o $outdir/CSS_normalized_output/beta_diversity/permdisp_out/$line/$method/" >> $log
		( compare_categories.py --method permdisp -i $dm -m $mapfile -c $line -o $outdir/CSS_normalized_output/beta_diversity/permdisp_out/$line/$method/ >/dev/null 2>&1 || true ) &
		done
	done
	wait
	echo "" >> $log

	for line in `cat $catlist`; do
		for dm in $outdir/CSS_normalized_output/beta_diversity/*_dm.txt; do
		method=$(basename $dm _dm.txt)
		echo "Category: $line" >> $outdir/CSS_normalized_output/beta_diversity/permdisp_results_collated.txt
		echo "Method: $method" >> $outdir/CSS_normalized_output/beta_diversity/permdisp_results_collated.txt
		cat $outdir/CSS_normalized_output/beta_diversity/permdisp_out/$line/$method/permdisp_results.txt >> $outdir/CSS_normalized_output/beta_diversity/permdisp_results_collated.txt 2>/dev/null || true
		echo "" >> $outdir/CSS_normalized_output/beta_diversity/permdisp_results_collated.txt
		done
	done
	wait
	fi

	if [[ ! -f $outdir/CSS_normalized_output/beta_diversity/anosim_results_collated.txt ]]; then
echo "Running ANOSIM tests."
echo "ANOSIM:" >> $log
	for line in `cat $catlist`; do
		for dm in $outdir/CSS_normalized_output/beta_diversity/*_dm.txt; do
		method=$(basename $dm _dm.txt)
		while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
		sleep 1
		done
		echo "	compare_categories.py --method anosim -i $dm -m $mapfile -c $line -o $outdir/CSS_normalized_output/beta_diversity/anosim_out/$line/$method/" >> $log
		( compare_categories.py --method anosim -i $dm -m $mapfile -c $line -o $outdir/CSS_normalized_output/beta_diversity/anosim_out/$line/$method/ 2>/dev/null 2>&1 || true ) &
		done
	done
	wait
	echo "" >> $log

	for line in `cat $catlist`; do
		for dm in $outdir/CSS_normalized_output/beta_diversity/*_dm.txt; do
		method=$(basename $dm _dm.txt)
		echo "Category: $line" >> $outdir/CSS_normalized_output/beta_diversity/anosim_results_collated.txt
		echo "Method: $method" >> $outdir/CSS_normalized_output/beta_diversity/anosim_results_collated.txt
		cat $outdir/CSS_normalized_output/beta_diversity/anosim_out/$line/$method/anosim_results.txt >> $outdir/CSS_normalized_output/beta_diversity/anosim_results_collated.txt 2>/dev/null || true
		echo "" >> $outdir/CSS_normalized_output/beta_diversity/anosim_results_collated.txt
		done
	done
	wait
	fi

	if [[ ! -f $outdir/CSS_normalized_output/beta_diversity/dbrda_results_collated.txt ]]; then
echo "Running DB-RDA tests."
echo "DB-RDA:" >> $log
	for line in `cat $catlist`; do
		for dm in $outdir/CSS_normalized_output/beta_diversity/*_dm.txt; do
		method=$(basename $dm _dm.txt)
		while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
		sleep 1
		done
		echo "	compare_categories.py --method dbrda -i $dm -m $mapfile -c $line -o $outdir/CSS_normalized_output/beta_diversity/dbrda_out/$line/$method/" >> $log
		( compare_categories.py --method dbrda -i $dm -m $mapfile -c $line -o $outdir/CSS_normalized_output/beta_diversity/dbrda_out/$line/$method/ 2>/dev/null 2>&1 || true ) &
		done
	done
	wait
	echo "" >> $log

	for line in `cat $catlist`; do
		for dm in $outdir/CSS_normalized_output/beta_diversity/*_dm.txt; do
		method=$(basename $dm _dm.txt)
		echo "Category: $line" >> $outdir/CSS_normalized_output/beta_diversity/dbrda_results_collated.txt
		echo "Method: $method" >> $outdir/CSS_normalized_output/beta_diversity/dbrda_results_collated.txt
		cat $outdir/CSS_normalized_output/beta_diversity/dbrda_out/$line/$method/dbrda_results.txt >> $outdir/CSS_normalized_output/beta_diversity/dbrda_results_collated.txt 2>/dev/null || true
		echo "" >> $outdir/CSS_normalized_output/beta_diversity/dbrda_results_collated.txt
		done
	done
	wait
	fi

	if [[ ! -f $outdir/CSS_normalized_output/beta_diversity/adonis_results_collated.txt ]]; then
echo "Running Adonis tests."
echo "Adonis:" >> $log
	for line in `cat $catlist`; do
		for dm in $outdir/CSS_normalized_output/beta_diversity/*_dm.txt; do
		method=$(basename $dm _dm.txt)
		while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
		sleep 1
		done
		echo "	compare_categories.py --method adonis -i $dm -m $mapfile -c $line -o $outdir/CSS_normalized_output/beta_diversity/adonis_out/$line/$method/" >> $log
		( compare_categories.py --method adonis -i $dm -m $mapfile -c $line -o $outdir/CSS_normalized_output/beta_diversity/adonis_out/$line/$method/ 2>/dev/null 2>&1 || true ) &
		done
	done
	wait
	echo "" >> $log

	for line in `cat $catlist`; do
		for dm in $outdir/CSS_normalized_output/beta_diversity/*_dm.txt; do
		method=$(basename $dm _dm.txt)
		echo "Category: $line" >> $outdir/CSS_normalized_output/beta_diversity/adonis_results_collated.txt
		echo "Method: $method" >> $outdir/CSS_normalized_output/beta_diversity/adonis_results_collated.txt
		cat $outdir/CSS_normalized_output/beta_diversity/adonis_out/$line/$method/adonis_results.txt >> $outdir/CSS_normalized_output/beta_diversity/adonis_results_collated.txt 2>/dev/null || true
		echo "" >> $outdir/CSS_normalized_output/beta_diversity/adonis_results_collated.txt
		done
	done
	wait
	fi
else
echo "
Categorical comparisons already present." >> $log
fi
	## Update HTML output
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

## Distance boxplots for each category
	boxplotscount=`ls $outdir/CSS_normalized_output/beta_diversity/*_boxplots 2>/dev/null | wc -l`
	if [[ $boxplotscount == 0 ]]; then
	echo "
Make distance boxplots commands:" >> $log
	echo "
Generating distance boxplots."
	for line in `cat $catlist`; do
		for dm in $outdir/CSS_normalized_output/beta_diversity/*_dm.txt; do
		dmbase=$(basename $dm _dm.txt)
		while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
		sleep 1
		done
		echo "	make_distance_boxplots.py -d $outdir/CSS_normalized_output/beta_diversity/${dmbase}_dm.txt -f $line -o $outdir/CSS_normalized_output/beta_diversity/${dmbase}_boxplots/ -m $mapfile -n 999" >> $log
		( make_distance_boxplots.py -d $outdir/CSS_normalized_output/beta_diversity/${dmbase}_dm.txt -f $line -o $outdir/CSS_normalized_output/beta_diversity/${dmbase}_boxplots/ -m $mapfile -n 999 >/dev/null 2>&1 || true ) &
		done
	done
	wait
	echo "" >> $log
	else
	echo "
Boxplots already present." >> $log
	fi

	## Update HTML output
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

## Make biplots
	if [[ ! -d $outdir/CSS_normalized_output/beta_diversity/biplots ]]; then
	echo "
Make biplots commands:" >> $log
	echo "
Generating PCoA biplots."
	mkdir $outdir/CSS_normalized_output/beta_diversity/biplots
	for pc in $outdir/CSS_normalized_output/beta_diversity/*_pc.txt; do
	pcmethod=$(basename $pc _pc.txt)
	mkdir $outdir/CSS_normalized_output/beta_diversity/biplots/$pcmethod
	done
	wait

	for pc in $outdir/CSS_normalized_output/beta_diversity/*_pc.txt; do
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	pcmethod=$(basename $pc _pc.txt)
		for level in $outdir/CSS_normalized_output/beta_diversity/summarized_tables/CSS_table_sorted_*.txt; do
		L=$(basename $level .txt)
		echo "	make_emperor.py -i $pc -m $mapfile -o $outdir/CSS_normalized_output/beta_diversity/biplots/$pcmethod/$L -t $level --add_unique_columns --ignore_missing_samples" >> $log
		( make_emperor.py -i $pc -m $mapfile -o $outdir/CSS_normalized_output/beta_diversity/biplots/$pcmethod/$L -t $level --add_unique_columns --ignore_missing_samples >/dev/null 2>&1 || true ) &
		done
	done
	wait
	echo "" >> $log
	else
	echo "
Biplots already present." >> $log
	fi

	## Update HTML output
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

## Run supervised learning on data using supplied categories
	if [[ ! -d $outdir/CSS_normalized_output/SupervisedLearning ]]; then
	mkdir $outdir/CSS_normalized_output/SupervisedLearning
	echo "
Supervised learning commands:" >> $log
	echo "
Running supervised learning analysis."
	for category in `cat $catlist`; do
		while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
		sleep 1
		done
		echo "	supervised_learning.py -i $CSSsort -m $mapfile -c $category -o $outdir/CSS_normalized_output/SupervisedLearning/$category --ntree 1000" >> $log
		( supervised_learning.py -i $CSSsort -m $mapfile -c $category -o $outdir/CSS_normalized_output/SupervisedLearning/$category --ntree 1000 &>/dev/null 2>&1 || true ) &
	done
	else
	echo "
Supervised Learning already present." >> $log
	fi

	## Update HTML output
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

## Make rank abundance plots (normalized)
	if [[ ! -d $outdir/CSS_normalized_output/RankAbundance ]]; then
	mkdir $outdir/CSS_normalized_output/RankAbundance
	echo "
Rank abundance plot commands:" >> $log
	echo "
Generating rank abundance plots."
	echo "	plot_rank_abundance_graph.py -i $CSSsort -o $outdir/CSS_normalized_output/RankAbundance/rankabund_xlog-ylog.pdf -s "*" -n
	plot_rank_abundance_graph.py -i $CSSsort -o $outdir/CSS_normalized_output/RankAbundance/rankabund_xlinear-ylog.pdf -s "*" -n -x
	plot_rank_abundance_graph.py -i $CSSsort -o $outdir/CSS_normalized_output/RankAbundance/rankabund_xlog-ylinear.pdf -s "*" -n -y
	plot_rank_abundance_graph.py -i $CSSsort -o $outdir/CSS_normalized_output/RankAbundance/rankabund_xlinear-ylinear.pdf -s "*" -n -x -y
	" >> $log
	( plot_rank_abundance_graph.py -i $CSSsort -o $outdir/CSS_normalized_output/RankAbundance/rankabund_xlog-ylog.pdf -s "*" -n ) &
	( plot_rank_abundance_graph.py -i $CSSsort -o $outdir/CSS_normalized_output/RankAbundance/rankabund_xlinear-ylog.pdf -s "*" -n -x ) &
	( plot_rank_abundance_graph.py -i $CSSsort -o $outdir/CSS_normalized_output/RankAbundance/rankabund_xlog-ylinear.pdf -s "*" -n -y ) &
	( plot_rank_abundance_graph.py -i $CSSsort -o $outdir/CSS_normalized_output/RankAbundance/rankabund_xlinear-ylinear.pdf -s "*" -n -x -y ) &
	fi
wait

	## Update HTML output
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

#######################################
## Start of taxonomy plotting steps

## Plot taxa summaries
		taxaout="$outdir/CSS_normalized_output/taxa_plots"
		if [[ ! -d $taxaout ]]; then
	echo "
Plotting taxonomy by sample."
	echo "
Plot taxa summaries command:
	plot_taxa_summary.py -i $outdir/CSS_normalized_output/beta_diversity/summarized_tables/CSS_table_sorted_L2.txt,$outdir/CSS_normalized_output/beta_diversity/summarized_tables/CSS_table_sorted_L3.txt,$outdir/CSS_normalized_output/beta_diversity/summarized_tables/CSS_table_sorted_L4.txt,$outdir/CSS_normalized_output/beta_diversity/summarized_tables/CSS_table_sorted_L5.txt,$outdir/CSS_normalized_output/beta_diversity/summarized_tables/CSS_table_sorted_L6.txt,$outdir/CSS_normalized_output/beta_diversity/summarized_tables/CSS_table_sorted_L7.txt -o $taxaout/taxa_summary_plots/ -c bar" >> $log
	plot_taxa_summary.py -i $outdir/CSS_normalized_output/beta_diversity/summarized_tables/CSS_table_sorted_L2.txt,$outdir/CSS_normalized_output/beta_diversity/summarized_tables/CSS_table_sorted_L3.txt,$outdir/CSS_normalized_output/beta_diversity/summarized_tables/CSS_table_sorted_L4.txt,$outdir/CSS_normalized_output/beta_diversity/summarized_tables/CSS_table_sorted_L5.txt,$outdir/CSS_normalized_output/beta_diversity/summarized_tables/CSS_table_sorted_L6.txt,$outdir/CSS_normalized_output/beta_diversity/summarized_tables/CSS_table_sorted_L7.txt -o $taxaout/taxa_summary_plots/ -c bar -l Phylum,Class,Order,Family,Genus,Species 1> $stdout 2> $stderr || true
	wait
		bash $scriptdir/log_slave.sh $stdout $stderr $log
		fi

## Taxa summaries for each category
	for line in `cat $catlist`; do
		taxaout="$outdir/CSS_normalized_output/taxa_plots_${line}"
		if [[ ! -d $taxaout ]]; then
	echo "
Building taxonomy plots for category: $line."
	echo "
Summarize taxa commands by category \"$line\":
	collapse_samples.py -m ${mapfile} -b ${CSSsort} --output_biom_fp ${taxaout}/${line}_otu_table.biom --output_mapping_fp ${taxaout}/${line}_map.txt --collapse_fields $line
	sort_otu_table.py -i ${taxaout}/${line}_otu_table.biom -o ${taxaout}/${line}_otu_table_sorted.biom
	summarize_taxa.py -i ${taxaout}/${line}_otu_table_sorted.biom -o ${taxaout}/  -L 2,3,4,5,6,7 -a
	plot_taxa_summary.py -i ${taxaout}/${line}_otu_table_sorted_L2.txt,${taxaout}/${line}_otu_table_sorted_L3.txt,${taxaout}/${line}_otu_table_sorted_L4.txt,${taxaout}/${line}_otu_table_sorted_L5.txt,${taxaout}/${line}_otu_table_sorted_L6.txt,${taxaout}/${line}_otu_table_sorted_L7.txt -o ${taxaout}/taxa_summary_plots/ -c bar,pie" >> $log

		mkdir $taxaout

	collapse_samples.py -m ${mapfile} -b ${CSSsort} --output_biom_fp ${taxaout}/${line}_otu_table.biom --output_mapping_fp ${taxaout}/${line}_map.txt --collapse_fields $line 1> $stdout 2> $stderr || true
	wait
		bash $scriptdir/log_slave.sh $stdout $stderr $log
		wait
	sort_otu_table.py -i ${taxaout}/${line}_otu_table.biom -o ${taxaout}/${line}_otu_table_sorted.biom 1> $stdout 2> $stderr || true
	wait
		bash $scriptdir/log_slave.sh $stdout $stderr $log
		wait
	summarize_taxa.py -i ${taxaout}/${line}_otu_table_sorted.biom -o ${taxaout}/  -L 2,3,4,5,6,7 -a 1> $stdout 2> $stderr || true
	wait
		bash $scriptdir/log_slave.sh $stdout $stderr $log
		wait
	plot_taxa_summary.py -i ${taxaout}/${line}_otu_table_sorted_L2.txt,${taxaout}/${line}_otu_table_sorted_L3.txt,${taxaout}/${line}_otu_table_sorted_L4.txt,${taxaout}/${line}_otu_table_sorted_L5.txt,${taxaout}/${line}_otu_table_sorted_L6.txt,${taxaout}/${line}_otu_table_sorted_L7.txt -o ${taxaout}/taxa_summary_plots/ -c bar,pie -l Phylum,Class,Order,Family,Genus,Species -d 300 -w 0.65 -x 8 -y 10 1> $stdout 2> $stderr || true
	wait
		bash $scriptdir/log_slave.sh $stdout $stderr $log
		wait
		fi
	done

	## Update HTML output
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

############################
## Group comparison steps

## Group significance for each category (Kruskal-Wallis, ANCOM, indicator species)

	## Kruskal-Wallis
	kwout="$outdir/CSS_normalized_output/KruskalWallis/"
	kwtestcount=$(ls $kwout/kruskalwallis_* 2> /dev/null | wc -l)
	if [[ $kwtestcount == 0 ]]; then
	echo "
Group significance commands:" >> $log
	if [[ ! -d $kwout ]]; then
	mkdir $kwout
	fi
	CSSsortrel="$outdir/OTU_tables/CSS_table_sorted_relativized.biom"
	if [[ ! -f $CSSsortrel ]]; then
	echo "
Relativizing OTU table:
	relativize_otu_table.py -i $CSSsort" >> $log
	relativize_otu_table.py -i $CSSsort >/dev/null 2>&1 || true
	fi
		CSSsortreltxt="$outdir/OTU_tables/CSS_table_sorted_relativized.txt"
		if [[ ! -f $CSSsortreltxt ]]; then
		biomtotxt.sh $CSSsortrel &>/dev/null
		fi
	echo "
Calculating Kruskal-Wallis test statistics when possible."
for line in `cat $catlist`; do
	if [[ ! -f $kwout/kruskalwallis_${line}_OTU.txt ]]; then
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	echo "	group_significance.py -i $CSSsortrel -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_OTU.txt -s kruskal_wallis" >> $log
	( group_significance.py -i $CSSsortrel -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_OTU.txt -s kruskal_wallis ) >/dev/null 2>&1 || true &
	fi
done
wait
for line in `cat $catlist`; do
	if [[ ! -f $kwout/kruskalwallis_$line\_L2.txt ]]; then
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	echo "	group_significance.py -i $outdir/CSS_normalized_output/beta_diversity/summarized_tables/CSS_table_sorted_L2.biom -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_L2.txt -s kruskal_wallis" >> $log
	( group_significance.py -i $outdir/CSS_normalized_output/beta_diversity/summarized_tables/CSS_table_sorted_L2.biom -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_L2.txt -s kruskal_wallis ) >/dev/null 2>&1 || true &
	fi
done
wait
for line in `cat $catlist`; do
	if [[ ! -f $kwout/kruskalwallis_$line\_L3.txt ]]; then
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	echo "	group_significance.py -i $outdir/CSS_normalized_output/beta_diversity/summarized_tables/CSS_table_sorted_L3.biom -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_L3.txt -s kruskal_wallis" >> $log
	( group_significance.py -i $outdir/CSS_normalized_output/beta_diversity/summarized_tables/CSS_table_sorted_L3.biom -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_L3.txt -s kruskal_wallis ) >/dev/null 2>&1 || true &
	fi
done
wait
for line in `cat $catlist`; do
	if [[ ! -f $kwout/kruskalwallis_$line\_L4.txt ]]; then
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	echo "	group_significance.py -i $outdir/CSS_normalized_output/beta_diversity/summarized_tables/CSS_table_sorted_L4.biom -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_L4.txt -s kruskal_wallis" >> $log
	( group_significance.py -i $outdir/CSS_normalized_output/beta_diversity/summarized_tables/CSS_table_sorted_L4.biom -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_L4.txt -s kruskal_wallis ) >/dev/null 2>&1 || true &
	fi
done
wait
for line in `cat $catlist`; do
	if [[ ! -f $kwout/kruskalwallis_$line\_L5.txt ]]; then
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	echo "	group_significance.py -i $outdir/CSS_normalized_output/beta_diversity/summarized_tables/CSS_table_sorted_L5.biom -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_L5.txt -s kruskal_wallis" >> $log
	( group_significance.py -i $outdir/CSS_normalized_output/beta_diversity/summarized_tables/CSS_table_sorted_L5.biom -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_L5.txt -s kruskal_wallis ) >/dev/null 2>&1 || true &
	fi
done
wait
for line in `cat $catlist`; do
	if [[ ! -f $kwout/kruskalwallis_$line\_L6.txt ]]; then
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	echo "	group_significance.py -i $outdir/CSS_normalized_output/beta_diversity/summarized_tables/CSS_table_sorted_L6.biom -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_L6.txt -s kruskal_wallis" >> $log
	( group_significance.py -i $outdir/CSS_normalized_output/beta_diversity/summarized_tables/CSS_table_sorted_L6.biom -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_L6.txt -s kruskal_wallis ) >/dev/null 2>&1 || true &
	fi
done
wait
for line in `cat $catlist`; do
	if [[ ! -f $kwout/kruskalwallis_$line\_L7.txt ]]; then
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	echo "	group_significance.py -i $outdir/CSS_normalized_output/beta_diversity/summarized_tables/CSS_table_sorted_L7.biom -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_L7.txt -s kruskal_wallis" >> $log
	( group_significance.py -i $outdir/CSS_normalized_output/beta_diversity/summarized_tables/CSS_table_sorted_L7.biom -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_L7.txt -s kruskal_wallis ) >/dev/null 2>&1 || true &
	fi
done
fi
wait
	## Update HTML output
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

	## Make OTU table output with absolute counts
	sumtables="$outdir/CSS_normalized_output/OTU_tables/"
	sumtablesabs=$(readlink -m $sumtables)
	if [[ ! -d "$sumtables" ]]; then
		mkdir -p $sumtables
	fi
	rm $sumtables/* 2>/dev/null
	if [[ -f "$outdir/OTU_tables/CSS_table_sorted.biom" ]]; then
		cp $outdir/OTU_tables/CSS_table_sorted.biom $sumtables

	## Summarize the sorted table and produce a list of tables to process in a variable
		summarize_taxa.py -i $sumtables/CSS_table_sorted.biom -L 2,3,4,5,6,7 --suppress_classic_table_output -a -o $sumtables
		wait
	fi

	## Remove OTU-level table
	rm $sumtables/CSS_table_sorted.biom

	## ANCOM
	ancomtoprocess=$(ls $sumtables 2>/dev/null)
	ancout="$outdir/CSS_normalized_output/ANCOM/"
	if [[ ! -d "$ancout" ]]; then
	echo "
Calculating ANCOM test statistics when possible."

	## Set up ANCOM output directory
	antestcount=$(ls $ancout/ANCOM_* 2> /dev/null | wc -l)
	if [[ $antestcount == 0 ]]; then
	echo "
ANCOM commands:" >> $log
		if [[ ! -d $ancout ]]; then
			mkdir -p $ancout
		fi
		cp $sumtables/*.biom $ancout/
		cd $ancout
		wait

	## Nested for loops to process ANCOM stats
	for line in `cat $catlist`; do
		while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
		sleep 1
		done
		for ancomtable in $ancomtoprocess; do
		echo "ancomR.sh $ancomtable $mapfileabs $line 0.05 $cores" >> $log
		ancomR.sh $ancomtable $mapfileabs $line 0.05 $cores >/dev/null 2>&1 || true &
		done
	done
	wait
	echo "" >> $log
	rm *.biom
	cd $workdir

	fi
	fi

wait
	## Update HTML output
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

	## Indicator species analysis
	cd $workdir
	indicout="$outdir/CSS_normalized_output/Indicator_species/"
	if [[ ! -d "$indicout" ]]; then
	echo "
Calculating indicator species analysis test statistics when possible."

	## Set up Indicator species output directory
	indictestcount=$(ls $indicout/Indicspecies_* 2> /dev/null | wc -l)
	if [[ $indictestcount == 0 ]]; then
	echo "
Indicator species commands:" >> $log
		if [[ ! -d $indicout ]]; then
			mkdir -p $indicout
		fi
		cp $sumtables/*.biom $indicout
		cd $indicout
		wait

	## Nested for loops to process Indicator species stats
	for line in `cat $catlist`; do
		while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
		sleep 1
		done
		for indictable in $ancomtoprocess; do
		echo "indicator_species.sh $mapfileabs $indictable $line 9999" >> $log
		( indicator_species.sh $mapfileabs $indictable $line 9999 ) >/dev/null 2>&1 || true &
		done
	done
	wait
	echo "" >> $log
	rm *.biom
	cd $workdir
	fi

wait
	## Update HTML output
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase
	fi

echo "
********************************************************************************

END OF CSS NORMALIZED TABLE PROCESSING STEPS

********************************************************************************
" >> $log
	fi

################################################################################
## START OF DESeq2 NORMALIZED ANALYSIS HERE

	if [[ "$desnorm" == "yes" ]]; then
echo "
********************************************************************************

DESeq2 NORMALIZED TABLE PROCESSING STARTS HERE

********************************************************************************
" >> $log

	echo "
Processing DESeq2 normalized table."
	echo "
Processing DESeq2 normalized table." >> $log

## Produce summary plots first through phyloseq (in parallel)



## Summarize taxa (yields relative abundance tables)
	if [[ ! -d $outdir/DESeq2_normalized_output/beta_diversity/summarized_tables ]]; then
	echo "
Summarize taxa command:
	summarize_taxa.py -i $DESeq2sort -o $outdir/DESeq2_normalized_output/beta_diversity/summarized_tables -L 2,3,4,5,6,7" >> $log
	echo "
Summarizing taxonomy by sample and building plots."
	summarize_taxa.py -i $DESeq2sort -o $outdir/DESeq2_normalized_output/beta_diversity/summarized_tables -L 2,3,4,5,6,7 1> $stdout 2> $stderr
	bash $scriptdir/log_slave.sh $stdout $stderr $log
	
	else
	echo "
Relative abundance tables already present." >> $log
	fi
	wait

## Beta diversity
	if [[ "$phylogenetic" == "YES" ]]; then
	if [[ ! -f $outdir/DESeq2_normalized_output/beta_diversity/bray_curtis_dm.txt && ! -f $outdir/DESeq2_normalized_output/beta_diversity/chord_dm.txt && ! -f $outdir/DESeq2_normalized_output/beta_diversity/hellinger_dm.txt && ! -f $outdir/DESeq2_normalized_output/beta_diversity/kulczynski_dm.txt && ! -f $outdir/DESeq2_normalized_output/beta_diversity/unweighted_unifrac_dm.txt && ! -f $outdir/DESeq2_normalized_output/beta_diversity/weighted_unifrac_dm.txt ]]; then
	echo "
Parallel beta diversity command:
	parallel_beta_diversity.py -i $DESeq2sort -o $outdir/DESeq2_normalized_output/beta_diversity/ --metrics $metrics -T  -t $tree --jobs_to_start $cores" >> $log
	echo "
Calculating beta diversity distance matrices."
	parallel_beta_diversity.py -i $DESeq2sort -o $outdir/DESeq2_normalized_output/beta_diversity/ --metrics $metrics -T  -t $tree --jobs_to_start $cores 1> $stdout 2> $stderr
	bash $scriptdir/log_slave.sh $stdout $stderr $log
	fi
	elif [[ "$phylogenetic" == "NO" ]]; then
	if [[ ! -f $outdir/DESeq2_normalized_output/beta_diversity/bray_curtis_dm.txt && ! -f $outdir/DESeq2_normalized_output/beta_diversity/chord_dm.txt && ! -f $outdir/DESeq2_normalized_output/beta_diversity/hellinger_dm.txt && ! -f $outdir/DESeq2_normalized_output/beta_diversity/kulczynski_dm.txt ]]; then
	echo "
Parallel beta diversity command:
	parallel_beta_diversity.py -i $DESeq2sort -o $outdir/DESeq2_normalized_output/beta_diversity/ --metrics $metrics -T --jobs_to_start $cores" >> $log
	echo "
Calculating beta diversity distance matrices."
	parallel_beta_diversity.py -i $DESeq2sort -o $outdir/DESeq2_normalized_output/beta_diversity/ --metrics $metrics -T --jobs_to_start $cores 1> $stdout 2> $stderr
	bash $scriptdir/log_slave.sh $stdout $stderr $log
	fi
	else
	echo "
Beta diversity matrices already present." >> $log
	fi
	wait

## Rename output files
	if [[ ! -f $outdir/DESeq2_normalized_output/beta_diversity/bray_curtis_dm.txt ]]; then
	bcdm=$(ls $outdir/DESeq2_normalized_output/beta_diversity/bray_curtis_*.txt)
	mv $bcdm $outdir/DESeq2_normalized_output/beta_diversity/bray_curtis_dm.txt 2>/dev/null
	fi
	wait
	if [[ ! -f $outdir/DESeq2_normalized_output/beta_diversity/chord_dm.txt ]]; then
	cdm=$(ls $outdir/DESeq2_normalized_output/beta_diversity/chord_*.txt)
	mv $cdm $outdir/DESeq2_normalized_output/beta_diversity/chord_dm.txt 2>/dev/null
	fi
	wait
	if [[ ! -f $outdir/DESeq2_normalized_output/beta_diversity/hellinger_dm.txt ]]; then
	hdm=$(ls $outdir/DESeq2_normalized_output/beta_diversity/hellinger_*.txt)
	mv $hdm $outdir/DESeq2_normalized_output/beta_diversity/hellinger_dm.txt 2>/dev/null
	fi
	wait
	if [[ ! -f $outdir/DESeq2_normalized_output/beta_diversity/kulczynski_dm.txt ]]; then
	kdm=$(ls $outdir/DESeq2_normalized_output/beta_diversity/kulczynski_*.txt)
	mv $kdm $outdir/DESeq2_normalized_output/beta_diversity/kulczynski_dm.txt 2>/dev/null
	fi
	wait
	if [[ "$phylogenetic" == "YES" ]]; then
	if [[ ! -f $outdir/DESeq2_normalized_output/beta_diversity/unweighted_unifrac_dm.txt ]]; then
	uudm=$(ls $outdir/DESeq2_normalized_output/beta_diversity/unweighted_unifrac_*.txt)
	mv $uudm $outdir/DESeq2_normalized_output/beta_diversity/unweighted_unifrac_dm.txt 2>/dev/null
	fi
	wait
	if [[ ! -f $outdir/DESeq2_normalized_output/beta_diversity/weighted_unifrac_dm.txt ]]; then
	wudm=$(ls $outdir/DESeq2_normalized_output/beta_diversity/weighted_unifrac_*.txt)
	mv $wudm $outdir/DESeq2_normalized_output/beta_diversity/weighted_unifrac_dm.txt 2>/dev/null
	fi
	wait
	fi
	wait

## Principal coordinates and NMDS commands
	pcoacoordscount=`ls $outdir/DESeq2_normalized_output/beta_diversity/*_pc.txt 2>/dev/null | wc -l`
	nmdscoordscount=`ls $outdir/DESeq2_normalized_output/beta_diversity/*_nmds.txt 2>/dev/null | wc -l`
	nmdsconvertcoordscount=`ls $outdir/DESeq2_normalized_output/beta_diversity/*_nmds_converted.txt 2>/dev/null | wc -l`
	if [[ $pcoacoordscount == 0 && $nmdscoordscount == 0 && $nmdsconvertcoordscount == 0 ]]; then
	echo "
Principal coordinates and NMDS commands." >> $log
	echo "
Constructing PCoA and NMDS coordinate files."
	echo "Principal coordinates:" >> $log
	for dm in $outdir/DESeq2_normalized_output/beta_diversity/*_dm.txt; do
	dmbase=$(basename $dm _dm.txt)
	echo "	principal_coordinates.py -i $dm -o $outdir/DESeq2_normalized_output/beta_diversity/${dmbase}_pc.txt" >> $log
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	( principal_coordinates.py -i $dm -o $outdir/DESeq2_normalized_output/beta_diversity/${dmbase}_pc.txt >/dev/null 2>&1 || true ) &
	done
	wait
	echo "" >> $log

	echo "NMDS coordinates:" >> $log
	for dm in $outdir/DESeq2_normalized_output/beta_diversity/*_dm.txt; do
	dmbase=$(basename $dm _dm.txt)
	echo "	nmds.py -i $dm -o $outdir/DESeq2_normalized_output/beta_diversity/${dmbase}_nmds.txt" >> $log
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	( nmds.py -i $dm -o $outdir/DESeq2_normalized_output/beta_diversity/${dmbase}_nmds.txt >/dev/null 2>&1 || true ) &
	done
	wait
	echo "" >> $log

	echo "Convert NMDS coordinates:" >> $log
	for dm in $outdir/DESeq2_normalized_output/beta_diversity/*_dm.txt; do
	dmbase=$(basename $dm _dm.txt)
	echo "	python $scriptdir/convert_nmds_coords.py -i $outdir/DESeq2_normalized_output/beta_diversity/${dmbase}_nmds.txt -o $outdir/DESeq2_normalized_output/beta_diversity/${dmbase}_nmds_converted.txt" >> $log
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	( python $scriptdir/convert_nmds_coords.py -i $outdir/DESeq2_normalized_output/beta_diversity/${dmbase}_nmds.txt -o $outdir/DESeq2_normalized_output/beta_diversity/${dmbase}_nmds_converted.txt >/dev/null 2>&1 || true ) &
	done
	wait
	echo "" >> $log
	else
	echo "
PCoA and NMDS coordinate files already present." >> $log
	fi

## Make 3D emperor plots (PCoA)
	pcoaplotscount=`ls $outdir/DESeq2_normalized_output/beta_diversity/*_pcoa_plot 2>/dev/null | wc -l`
	if [[ $pcoaplotscount == 0 ]]; then
	echo "
Make emperor commands:" >> $log
	echo "
Generating 3D PCoA plots."
	echo "PCoA plots:" >> $log
	for pc in $outdir/DESeq2_normalized_output/beta_diversity/*_pc.txt; do
	pcbase=$(basename $pc _pc.txt)
		if [[ -d $outdir/DESeq2_normalized_output/beta_diversity/${pcbase}_emperor_pcoa_plot/ ]]; then
		rm -r $outdir/DESeq2_normalized_output/beta_diversity/${pcbase}_emperor_pcoa_plot/
		fi
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	echo "	make_emperor.py -i $pc -o $outdir/DESeq2_normalized_output/beta_diversity/${pcbase}_emperor_pcoa_plot/ -m $mapfile --add_unique_columns --ignore_missing_samples" >> $log
	( make_emperor.py -i $pc -o $outdir/DESeq2_normalized_output/beta_diversity/${pcbase}_emperor_pcoa_plot/ -m $mapfile --add_unique_columns --ignore_missing_samples >/dev/null 2>&1 || true ) &
	done
	wait
	echo "" >> $log
	else
	echo "
3D PCoA plots already present." >> $log
	fi

## Make 3D emperor plots (NMDS)
	nmdsplotscount=`ls $outdir/DESeq2_normalized_output/beta_diversity/*_nmds_plot 2>/dev/null | wc -l`
	if [[ $nmdsplotscount == 0 ]]; then
	echo "
Generating 3D NMDS plots."
	echo "NMDS plots:" >> $log
	for nmds in $outdir/DESeq2_normalized_output/beta_diversity/*_nmds_converted.txt; do
	nmdsbase=$(basename $nmds _nmds_converted.txt)
		if [[ -d $outdir/DESeq2_normalized_output/beta_diversity/${nmdsbase}_emperor_nmds_plot/ ]]; then
		rm -r $outdir/DESeq2_normalized_output/beta_diversity/${nmdsbase}_emperor_nmds_plot/
		fi
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	echo "	make_emperor.py -i $nmds -o $outdir/DESeq2_normalized_output/beta_diversity/${nmdsbase}_emperor_nmds_plot/ -m $mapfile --add_unique_columns --ignore_missing_samples" >> $log
	( make_emperor.py -i $nmds -o $outdir/DESeq2_normalized_output/beta_diversity/${nmdsbase}_emperor_nmds_plot/ -m $mapfile --add_unique_columns --ignore_missing_samples >/dev/null 2>&1 || true ) &
	done
	wait
	echo "" >> $log
	else
	echo "
3D NMDS plots already present." >> $log
	fi

	## Update HTML output
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

## Make 2D plots
	if [[ ! -d $outdir/DESeq2_normalized_output/beta_diversity/2D_PCoA_bdiv_plots ]]; then
	echo "
Make 2D PCoA plots commands:" >> $log
	echo "
Generating 2D PCoA plots."
	for pc in $outdir/DESeq2_normalized_output/beta_diversity/*_pc.txt; do
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	echo "	make_2d_plots.py -i $pc -m $mapfile -o $outdir/DESeq2_normalized_output/beta_diversity/2D_PCoA_bdiv_plots" >> $log
	( make_2d_plots.py -i $pc -m $mapfile -o $outdir/DESeq2_normalized_output/beta_diversity/2D_PCoA_bdiv_plots >/dev/null 2>&1 || true ) &
	done
	wait
	echo "" >> $log
	else
	echo "
2D plots already present." >> $log
	fi

	## Update HTML output
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

## Comparing categories statistics
if [[ ! -f $outdir/DESeq2_normalized_output/beta_diversity/permanova_results_collated.txt && ! -f $outdir/DESeq2_normalized_output/beta_diversity/permdisp_results_collated.txt && ! -f $outdir/DESeq2_normalized_output/beta_diversity/anosim_results_collated.txt && ! -f $outdir/DESeq2_normalized_output/beta_diversity/dbrda_results_collated.txt && ! -f $outdir/DESeq2_normalized_output/beta_diversity/adonis_results_collated.txt ]]; then
echo "
Compare categories commands:" >> $log
	echo "
Calculating one-way statsitics from distance matrices."
	if [[ ! -f $outdir/DESeq2_normalized_output/beta_diversity/permanova_results_collated.txt ]]; then
echo "Running PERMANOVA tests."
echo "PERMANOVA:" >> $log
	for line in `cat $catlist`; do
		for dm in $outdir/DESeq2_normalized_output/beta_diversity/*_dm.txt; do
		method=$(basename $dm _dm.txt)
		while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
		sleep 1
		done
		echo "	compare_categories.py --method permanova -i $dm -m $mapfile -c $line -o $outdir/DESeq2_normalized_output/beta_diversity/permanova_out/$line/$method/" >> $log
		( compare_categories.py --method permanova -i $dm -m $mapfile -c $line -o $outdir/DESeq2_normalized_output/beta_diversity/permanova_out/$line/$method/ >/dev/null 2>&1 || true ) &
		done
	done
	wait
	echo "" >> $log

	for line in `cat $catlist`; do
		for dm in $outdir/DESeq2_normalized_output/beta_diversity/*_dm.txt; do
		method=$(basename $dm _dm.txt)
		echo "Category: $line" >> $outdir/DESeq2_normalized_output/beta_diversity/permanova_results_collated.txt
		echo "Method: $method" >> $outdir/DESeq2_normalized_output/beta_diversity/permanova_results_collated.txt
		cat $outdir/DESeq2_normalized_output/beta_diversity/permanova_out/$line/$method/permanova_results.txt >> $outdir/DESeq2_normalized_output/beta_diversity/permanova_results_collated.txt 2>/dev/null || true
		echo "" >> $outdir/DESeq2_normalized_output/beta_diversity/permanova_results_collated.txt
		done
	done
	wait
	fi

	if [[ ! -f $outdir/DESeq2_normalized_output/beta_diversity/permdisp_results_collated.txt ]]; then
echo "Running PERMDISP tests."
echo "PERMDISP:" >> $log
	for line in `cat $catlist`; do
		for dm in $outdir/DESeq2_normalized_output/beta_diversity/*_dm.txt; do
		method=$(basename $dm _dm.txt)
		while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
		sleep 1
		done
		echo "	compare_categories.py --method permdisp -i $dm -m $mapfile -c $line -o $outdir/DESeq2_normalized_output/beta_diversity/permdisp_out/$line/$method/" >> $log
		( compare_categories.py --method permdisp -i $dm -m $mapfile -c $line -o $outdir/DESeq2_normalized_output/beta_diversity/permdisp_out/$line/$method/ >/dev/null 2>&1 || true ) &
		done
	done
	wait
	echo "" >> $log

	for line in `cat $catlist`; do
		for dm in $outdir/DESeq2_normalized_output/beta_diversity/*_dm.txt; do
		method=$(basename $dm _dm.txt)
		echo "Category: $line" >> $outdir/DESeq2_normalized_output/beta_diversity/permdisp_results_collated.txt
		echo "Method: $method" >> $outdir/DESeq2_normalized_output/beta_diversity/permdisp_results_collated.txt
		cat $outdir/DESeq2_normalized_output/beta_diversity/permdisp_out/$line/$method/permdisp_results.txt >> $outdir/DESeq2_normalized_output/beta_diversity/permdisp_results_collated.txt 2>/dev/null || true
		echo "" >> $outdir/DESeq2_normalized_output/beta_diversity/permdisp_results_collated.txt
		done
	done
	wait
	fi

	if [[ ! -f $outdir/DESeq2_normalized_output/beta_diversity/anosim_results_collated.txt ]]; then
echo "Running ANOSIM tests."
echo "ANOSIM:" >> $log
	for line in `cat $catlist`; do
		for dm in $outdir/DESeq2_normalized_output/beta_diversity/*_dm.txt; do
		method=$(basename $dm _dm.txt)
		while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
		sleep 1
		done
		echo "	compare_categories.py --method anosim -i $dm -m $mapfile -c $line -o $outdir/DESeq2_normalized_output/beta_diversity/anosim_out/$line/$method/" >> $log
		( compare_categories.py --method anosim -i $dm -m $mapfile -c $line -o $outdir/DESeq2_normalized_output/beta_diversity/anosim_out/$line/$method/ 2>/dev/null 2>&1 || true ) &
		done
	done
	wait
	echo "" >> $log

	for line in `cat $catlist`; do
		for dm in $outdir/DESeq2_normalized_output/beta_diversity/*_dm.txt; do
		method=$(basename $dm _dm.txt)
		echo "Category: $line" >> $outdir/DESeq2_normalized_output/beta_diversity/anosim_results_collated.txt
		echo "Method: $method" >> $outdir/DESeq2_normalized_output/beta_diversity/anosim_results_collated.txt
		cat $outdir/DESeq2_normalized_output/beta_diversity/anosim_out/$line/$method/anosim_results.txt >> $outdir/DESeq2_normalized_output/beta_diversity/anosim_results_collated.txt 2>/dev/null || true
		echo "" >> $outdir/DESeq2_normalized_output/beta_diversity/anosim_results_collated.txt
		done
	done
	wait
	fi

	if [[ ! -f $outdir/DESeq2_normalized_output/beta_diversity/dbrda_results_collated.txt ]]; then
echo "Running DB-RDA tests."
echo "DB-RDA:" >> $log
	for line in `cat $catlist`; do
		for dm in $outdir/DESeq2_normalized_output/beta_diversity/*_dm.txt; do
		method=$(basename $dm _dm.txt)
		while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
		sleep 1
		done
		echo "	compare_categories.py --method dbrda -i $dm -m $mapfile -c $line -o $outdir/DESeq2_normalized_output/beta_diversity/dbrda_out/$line/$method/" >> $log
		( compare_categories.py --method dbrda -i $dm -m $mapfile -c $line -o $outdir/DESeq2_normalized_output/beta_diversity/dbrda_out/$line/$method/ 2>/dev/null 2>&1 || true ) &
		done
	done
	wait
	echo "" >> $log

	for line in `cat $catlist`; do
		for dm in $outdir/DESeq2_normalized_output/beta_diversity/*_dm.txt; do
		method=$(basename $dm _dm.txt)
		echo "Category: $line" >> $outdir/DESeq2_normalized_output/beta_diversity/dbrda_results_collated.txt
		echo "Method: $method" >> $outdir/DESeq2_normalized_output/beta_diversity/dbrda_results_collated.txt
		cat $outdir/DESeq2_normalized_output/beta_diversity/dbrda_out/$line/$method/dbrda_results.txt >> $outdir/DESeq2_normalized_output/beta_diversity/dbrda_results_collated.txt 2>/dev/null || true
		echo "" >> $outdir/DESeq2_normalized_output/beta_diversity/dbrda_results_collated.txt
		done
	done
	wait
	fi

	if [[ ! -f $outdir/DESeq2_normalized_output/beta_diversity/adonis_results_collated.txt ]]; then
echo "Running Adonis tests."
echo "Adonis:" >> $log
	for line in `cat $catlist`; do
		for dm in $outdir/DESeq2_normalized_output/beta_diversity/*_dm.txt; do
		method=$(basename $dm _dm.txt)
		while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
		sleep 1
		done
		echo "	compare_categories.py --method adonis -i $dm -m $mapfile -c $line -o $outdir/DESeq2_normalized_output/beta_diversity/adonis_out/$line/$method/" >> $log
		( compare_categories.py --method adonis -i $dm -m $mapfile -c $line -o $outdir/DESeq2_normalized_output/beta_diversity/adonis_out/$line/$method/ 2>/dev/null 2>&1 || true ) &
		done
	done
	wait
	echo "" >> $log

	for line in `cat $catlist`; do
		for dm in $outdir/DESeq2_normalized_output/beta_diversity/*_dm.txt; do
		method=$(basename $dm _dm.txt)
		echo "Category: $line" >> $outdir/DESeq2_normalized_output/beta_diversity/adonis_results_collated.txt
		echo "Method: $method" >> $outdir/DESeq2_normalized_output/beta_diversity/adonis_results_collated.txt
		cat $outdir/DESeq2_normalized_output/beta_diversity/adonis_out/$line/$method/adonis_results.txt >> $outdir/DESeq2_normalized_output/beta_diversity/adonis_results_collated.txt 2>/dev/null || true
		echo "" >> $outdir/DESeq2_normalized_output/beta_diversity/adonis_results_collated.txt
		done
	done
	wait
	fi
else
echo "
Categorical comparisons already present." >> $log
fi
	## Update HTML output
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

## Distance boxplots for each category
	boxplotscount=`ls $outdir/DESeq2_normalized_output/beta_diversity/*_boxplots 2>/dev/null | wc -l`
	if [[ $boxplotscount == 0 ]]; then
	echo "
Make distance boxplots commands:" >> $log
	echo "
Generating distance boxplots."
	for line in `cat $catlist`; do
		for dm in $outdir/DESeq2_normalized_output/beta_diversity/*_dm.txt; do
		dmbase=$(basename $dm _dm.txt)
		while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
		sleep 1
		done
		echo "	make_distance_boxplots.py -d $outdir/DESeq2_normalized_output/beta_diversity/${dmbase}_dm.txt -f $line -o $outdir/DESeq2_normalized_output/beta_diversity/${dmbase}_boxplots/ -m $mapfile -n 999" >> $log
		( make_distance_boxplots.py -d $outdir/DESeq2_normalized_output/beta_diversity/${dmbase}_dm.txt -f $line -o $outdir/DESeq2_normalized_output/beta_diversity/${dmbase}_boxplots/ -m $mapfile -n 999 >/dev/null 2>&1 || true ) &
		done
	done
	wait
	echo "" >> $log
	else
	echo "
Boxplots already present." >> $log
	fi

	## Update HTML output
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

## Make biplots
	if [[ ! -d $outdir/DESeq2_normalized_output/beta_diversity/biplots ]]; then
	echo "
Make biplots commands:" >> $log
	echo "
Generating PCoA biplots."
	mkdir $outdir/DESeq2_normalized_output/beta_diversity/biplots
	for pc in $outdir/DESeq2_normalized_output/beta_diversity/*_pc.txt; do
	pcmethod=$(basename $pc _pc.txt)
	mkdir $outdir/DESeq2_normalized_output/beta_diversity/biplots/$pcmethod
	done
	wait

	for pc in $outdir/DESeq2_normalized_output/beta_diversity/*_pc.txt; do
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	pcmethod=$(basename $pc _pc.txt)
		for level in $outdir/DESeq2_normalized_output/beta_diversity/summarized_tables/DESeq2_table_sorted_*.txt; do
		L=$(basename $level .txt)
		echo "	make_emperor.py -i $pc -m $mapfile -o $outdir/DESeq2_normalized_output/beta_diversity/biplots/$pcmethod/$L -t $level --add_unique_columns --ignore_missing_samples" >> $log
		( make_emperor.py -i $pc -m $mapfile -o $outdir/DESeq2_normalized_output/beta_diversity/biplots/$pcmethod/$L -t $level --add_unique_columns --ignore_missing_samples >/dev/null 2>&1 || true ) &
		done
	done
	wait
	echo "" >> $log
	else
	echo "
Biplots already present." >> $log
	fi

	## Update HTML output
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

## Run supervised learning on data using supplied categories
	if [[ ! -d $outdir/DESeq2_normalized_output/SupervisedLearning ]]; then
	mkdir $outdir/DESeq2_normalized_output/SupervisedLearning
	echo "
Supervised learning commands:" >> $log
	echo "
Running supervised learning analysis."
	for category in `cat $catlist`; do
		while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
		sleep 1
		done
		echo "	supervised_learning.py -i $DESeq2sort -m $mapfile -c $category -o $outdir/DESeq2_normalized_output/SupervisedLearning/$category --ntree 1000" >> $log
		( supervised_learning.py -i $DESeq2sort -m $mapfile -c $category -o $outdir/DESeq2_normalized_output/SupervisedLearning/$category --ntree 1000 &>/dev/null 2>&1 || true ) &
	done
	else
	echo "
Supervised Learning already present." >> $log
	fi

	## Update HTML output
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

## Make rank abundance plots (normalized)
	if [[ ! -d $outdir/DESeq2_normalized_output/RankAbundance ]]; then
	mkdir $outdir/DESeq2_normalized_output/RankAbundance
	echo "
Rank abundance plot commands:" >> $log
	echo "
Generating rank abundance plots."
	echo "	plot_rank_abundance_graph.py -i $DESeq2sort -o $outdir/DESeq2_normalized_output/RankAbundance/rankabund_xlog-ylog.pdf -s "*" -n
	plot_rank_abundance_graph.py -i $DESeq2sort -o $outdir/DESeq2_normalized_output/RankAbundance/rankabund_xlinear-ylog.pdf -s "*" -n -x
	plot_rank_abundance_graph.py -i $DESeq2sort -o $outdir/DESeq2_normalized_output/RankAbundance/rankabund_xlog-ylinear.pdf -s "*" -n -y
	plot_rank_abundance_graph.py -i $DESeq2sort -o $outdir/DESeq2_normalized_output/RankAbundance/rankabund_xlinear-ylinear.pdf -s "*" -n -x -y
	" >> $log
	( plot_rank_abundance_graph.py -i $DESeq2sort -o $outdir/DESeq2_normalized_output/RankAbundance/rankabund_xlog-ylog.pdf -s "*" -n ) &
	( plot_rank_abundance_graph.py -i $DESeq2sort -o $outdir/DESeq2_normalized_output/RankAbundance/rankabund_xlinear-ylog.pdf -s "*" -n -x ) &
	( plot_rank_abundance_graph.py -i $DESeq2sort -o $outdir/DESeq2_normalized_output/RankAbundance/rankabund_xlog-ylinear.pdf -s "*" -n -y ) &
	( plot_rank_abundance_graph.py -i $DESeq2sort -o $outdir/DESeq2_normalized_output/RankAbundance/rankabund_xlinear-ylinear.pdf -s "*" -n -x -y ) &
	fi
wait

	## Update HTML output
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

#######################################
## Start of taxonomy plotting steps

## Plot taxa summaries
		taxaout="$outdir/DESeq2_normalized_output/taxa_plots"
		if [[ ! -d $taxaout ]]; then
	echo "
Plotting taxonomy by sample."
	echo "
Plot taxa summaries command:
	plot_taxa_summary.py -i $outdir/DESeq2_normalized_output/beta_diversity/summarized_tables/DESeq2_table_sorted_L2.txt,$outdir/DESeq2_normalized_output/beta_diversity/summarized_tables/DESeq2_table_sorted_L3.txt,$outdir/DESeq2_normalized_output/beta_diversity/summarized_tables/DESeq2_table_sorted_L4.txt,$outdir/DESeq2_normalized_output/beta_diversity/summarized_tables/DESeq2_table_sorted_L5.txt,$outdir/DESeq2_normalized_output/beta_diversity/summarized_tables/DESeq2_table_sorted_L6.txt,$outdir/DESeq2_normalized_output/beta_diversity/summarized_tables/DESeq2_table_sorted_L7.txt -o $taxaout/taxa_summary_plots/ -c bar" >> $log
	plot_taxa_summary.py -i $outdir/DESeq2_normalized_output/beta_diversity/summarized_tables/DESeq2_table_sorted_L2.txt,$outdir/DESeq2_normalized_output/beta_diversity/summarized_tables/DESeq2_table_sorted_L3.txt,$outdir/DESeq2_normalized_output/beta_diversity/summarized_tables/DESeq2_table_sorted_L4.txt,$outdir/DESeq2_normalized_output/beta_diversity/summarized_tables/DESeq2_table_sorted_L5.txt,$outdir/DESeq2_normalized_output/beta_diversity/summarized_tables/DESeq2_table_sorted_L6.txt,$outdir/DESeq2_normalized_output/beta_diversity/summarized_tables/DESeq2_table_sorted_L7.txt -o $taxaout/taxa_summary_plots/ -c bar -l Phylum,Class,Order,Family,Genus,Species 1> $stdout 2> $stderr || true
	wait
		bash $scriptdir/log_slave.sh $stdout $stderr $log
		fi

## Taxa summaries for each category
	for line in `cat $catlist`; do
		taxaout="$outdir/DESeq2_normalized_output/taxa_plots_${line}"
		if [[ ! -d $taxaout ]]; then
	echo "
Building taxonomy plots for category: $line."
	echo "
Summarize taxa commands by category \"$line\":
	collapse_samples.py -m ${mapfile} -b ${DESeq2sort} --output_biom_fp ${taxaout}/${line}_otu_table.biom --output_mapping_fp ${taxaout}/${line}_map.txt --collapse_fields $line
	sort_otu_table.py -i ${taxaout}/${line}_otu_table.biom -o ${taxaout}/${line}_otu_table_sorted.biom
	summarize_taxa.py -i ${taxaout}/${line}_otu_table_sorted.biom -o ${taxaout}/  -L 2,3,4,5,6,7 -a
	plot_taxa_summary.py -i ${taxaout}/${line}_otu_table_sorted_L2.txt,${taxaout}/${line}_otu_table_sorted_L3.txt,${taxaout}/${line}_otu_table_sorted_L4.txt,${taxaout}/${line}_otu_table_sorted_L5.txt,${taxaout}/${line}_otu_table_sorted_L6.txt,${taxaout}/${line}_otu_table_sorted_L7.txt -o ${taxaout}/taxa_summary_plots/ -c bar,pie" >> $log

		mkdir $taxaout

	collapse_samples.py -m ${mapfile} -b ${DESeq2sort} --output_biom_fp ${taxaout}/${line}_otu_table.biom --output_mapping_fp ${taxaout}/${line}_map.txt --collapse_fields $line 1> $stdout 2> $stderr || true
	wait
		bash $scriptdir/log_slave.sh $stdout $stderr $log
		wait
	sort_otu_table.py -i ${taxaout}/${line}_otu_table.biom -o ${taxaout}/${line}_otu_table_sorted.biom 1> $stdout 2> $stderr || true
	wait
		bash $scriptdir/log_slave.sh $stdout $stderr $log
		wait
	summarize_taxa.py -i ${taxaout}/${line}_otu_table_sorted.biom -o ${taxaout}/  -L 2,3,4,5,6,7 -a 1> $stdout 2> $stderr || true
	wait
		bash $scriptdir/log_slave.sh $stdout $stderr $log
		wait
	plot_taxa_summary.py -i ${taxaout}/${line}_otu_table_sorted_L2.txt,${taxaout}/${line}_otu_table_sorted_L3.txt,${taxaout}/${line}_otu_table_sorted_L4.txt,${taxaout}/${line}_otu_table_sorted_L5.txt,${taxaout}/${line}_otu_table_sorted_L6.txt,${taxaout}/${line}_otu_table_sorted_L7.txt -o ${taxaout}/taxa_summary_plots/ -c bar,pie -l Phylum,Class,Order,Family,Genus,Species -d 300 -w 0.65 -x 8 -y 10 1> $stdout 2> $stderr || true
	wait
		bash $scriptdir/log_slave.sh $stdout $stderr $log
		wait
		fi
	done

	## Update HTML output
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

############################
## Group comparison steps

## Group significance for each category (Kruskal-Wallis and nonparametric Ttest)

	## Kruskal-Wallis
	kwout="$outdir/DESeq2_normalized_output/KruskalWallis/"
	kwtestcount=$(ls $kwout/kruskalwallis_* 2> /dev/null | wc -l)
	if [[ $kwtestcount == 0 ]]; then
	echo "
Group significance commands:" >> $log
	if [[ ! -d $kwout ]]; then
	mkdir $kwout
	fi
	DESeq2sortrel="$outdir/OTU_tables/DESeq2_table_sorted_relativized.biom"
	if [[ ! -f $DESeq2sortrel ]]; then
	echo "
Relativizing OTU table:
	relativize_otu_table.py -i $DESeq2sort" >> $log
	relativize_otu_table.py -i $DESeq2sort >/dev/null 2>&1 || true
	fi
		DESeq2sortreltxt="$outdir/OTU_tables/DESeq2_table_sorted_relativized.txt"
		if [[ ! -f $DESeq2sortreltxt ]]; then
		biomtotxt.sh $DESeq2sortrel &>/dev/null
		fi
	echo "
Calculating Kruskal-Wallis test statistics when possible."
for line in `cat $catlist`; do
	if [[ ! -f $kwout/kruskalwallis_${line}_OTU.txt ]]; then
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	echo "	group_significance.py -i $DESeq2sortrel -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_OTU.txt -s kruskal_wallis" >> $log
	( group_significance.py -i $DESeq2sortrel -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_OTU.txt -s kruskal_wallis ) >/dev/null 2>&1 || true &
	fi
done
wait
for line in `cat $catlist`; do
	if [[ ! -f $kwout/kruskalwallis_$line\_L2.txt ]]; then
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	echo "	group_significance.py -i $outdir/DESeq2_normalized_output/beta_diversity/summarized_tables/DESeq2_table_sorted_L2.biom -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_L2.txt -s kruskal_wallis" >> $log
	( group_significance.py -i $outdir/DESeq2_normalized_output/beta_diversity/summarized_tables/DESeq2_table_sorted_L2.biom -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_L2.txt -s kruskal_wallis ) >/dev/null 2>&1 || true &
	fi
done
wait
for line in `cat $catlist`; do
	if [[ ! -f $kwout/kruskalwallis_$line\_L3.txt ]]; then
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	echo "	group_significance.py -i $outdir/DESeq2_normalized_output/beta_diversity/summarized_tables/DESeq2_table_sorted_L3.biom -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_L3.txt -s kruskal_wallis" >> $log
	( group_significance.py -i $outdir/DESeq2_normalized_output/beta_diversity/summarized_tables/DESeq2_table_sorted_L3.biom -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_L3.txt -s kruskal_wallis ) >/dev/null 2>&1 || true &
	fi
done
wait
for line in `cat $catlist`; do
	if [[ ! -f $kwout/kruskalwallis_$line\_L4.txt ]]; then
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	echo "	group_significance.py -i $outdir/DESeq2_normalized_output/beta_diversity/summarized_tables/DESeq2_table_sorted_L4.biom -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_L4.txt -s kruskal_wallis" >> $log
	( group_significance.py -i $outdir/DESeq2_normalized_output/beta_diversity/summarized_tables/DESeq2_table_sorted_L4.biom -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_L4.txt -s kruskal_wallis ) >/dev/null 2>&1 || true &
	fi
done
wait
for line in `cat $catlist`; do
	if [[ ! -f $kwout/kruskalwallis_$line\_L5.txt ]]; then
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	echo "	group_significance.py -i $outdir/DESeq2_normalized_output/beta_diversity/summarized_tables/DESeq2_table_sorted_L5.biom -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_L5.txt -s kruskal_wallis" >> $log
	( group_significance.py -i $outdir/DESeq2_normalized_output/beta_diversity/summarized_tables/DESeq2_table_sorted_L5.biom -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_L5.txt -s kruskal_wallis ) >/dev/null 2>&1 || true &
	fi
done
wait
for line in `cat $catlist`; do
	if [[ ! -f $kwout/kruskalwallis_$line\_L6.txt ]]; then
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	echo "	group_significance.py -i $outdir/DESeq2_normalized_output/beta_diversity/summarized_tables/DESeq2_table_sorted_L6.biom -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_L6.txt -s kruskal_wallis" >> $log
	( group_significance.py -i $outdir/DESeq2_normalized_output/beta_diversity/summarized_tables/DESeq2_table_sorted_L6.biom -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_L6.txt -s kruskal_wallis ) >/dev/null 2>&1 || true &
	fi
done
wait
for line in `cat $catlist`; do
	if [[ ! -f $kwout/kruskalwallis_$line\_L7.txt ]]; then
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	echo "	group_significance.py -i $outdir/DESeq2_normalized_output/beta_diversity/summarized_tables/DESeq2_table_sorted_L7.biom -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_L7.txt -s kruskal_wallis" >> $log
	( group_significance.py -i $outdir/DESeq2_normalized_output/beta_diversity/summarized_tables/DESeq2_table_sorted_L7.biom -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_L7.txt -s kruskal_wallis ) >/dev/null 2>&1 || true &
	fi
done
fi
wait
	## Update HTML output
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

	## Make OTU table output with absolute counts
	sumtables="$outdir/DESeq2_normalized_output/OTU_tables/"
	sumtablesabs=$(readlink -m $sumtables)
	if [[ ! -d "$sumtables" ]]; then
		mkdir -p $sumtables
	fi
	rm $sumtables/* 2>/dev/null
	if [[ -f "$outdir/OTU_tables/DESeq2_table_sorted.biom" ]]; then
		cp $outdir/OTU_tables/DESeq2_table_sorted.biom $sumtables

	## Summarize the sorted table and produce a list of tables to process in a variable
		summarize_taxa.py -i $sumtables/DESeq2_table_sorted.biom -L 2,3,4,5,6,7 --suppress_classic_table_output -a -o $sumtables
		wait
	fi

	## Remove OTU-level table
	rm $sumtables/DESeq2_table_sorted.biom

	## ANCOM
	ancomtoprocess=$(ls $sumtables 2>/dev/null)
	ancout="$outdir/DESeq2_normalized_output/ANCOM/"
	if [[ ! -d "$ancout" ]]; then
	echo "
Calculating ANCOM test statistics when possible."

	## Set up ANCOM output directory
	antestcount=$(ls $ancout/ANCOM_* 2> /dev/null | wc -l)
	if [[ $antestcount == 0 ]]; then
	echo "
ANCOM commands:" >> $log
		if [[ ! -d $ancout ]]; then
			mkdir -p $ancout
		fi
		cp $sumtables/*.biom $ancout/
		cd $ancout
#		cp $sumtablesabs/*.biom ./
		wait

	## Nested for loops to process ANCOM stats
	for line in `cat $catlist`; do
		while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
		sleep 1
		done
		for ancomtable in $ancomtoprocess; do
		echo "ancomR.sh $ancomtable $mapfileabs $line 0.05 $cores" >> $log
		ancomR.sh $ancomtable $mapfileabs $line 0.05 $cores >/dev/null 2>&1 || true &
		done
	done
	wait
	echo "" >> $log
	rm *.biom
	cd $workdir

	fi
	fi

wait
	## Update HTML output
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

	## Indicator species analysis
	cd $workdir
	indicout="$outdir/DESeq2_normalized_output/Indicator_species/"
	if [[ ! -d "$indicout" ]]; then
	echo "
Calculating indicator species analysis test statistics when possible."

	## Set up Indicator species output directory
	indictestcount=$(ls $indicout/Indicspecies_* 2> /dev/null | wc -l)
	if [[ $indictestcount == 0 ]]; then
	echo "
Indicator species commands:" >> $log
		if [[ ! -d $indicout ]]; then
			mkdir -p $indicout
		fi
		cp $sumtables/*.biom $indicout
		cd $indicout
		wait

	## Nested for loops to process Indicator species stats
	for line in `cat $catlist`; do
		while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
		sleep 1
		done
		for indictable in $ancomtoprocess; do
		echo "indicator_species.sh $mapfileabs $indictable $line 9999" >> $log
		( indicator_species.sh $mapfileabs $indictable $line 9999 ) >/dev/null 2>&1 || true &
		done
	done
	wait
	echo "" >> $log
	rm *.biom
	cd $workdir
	fi

wait
	## Update HTML output
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase
	fi

echo "
********************************************************************************

END OF DESeq2 NORMALIZED TABLE PROCESSING STEPS

********************************************************************************
" >> $log
	fi

################################################################################
## START OF RAREFIED ANALYSIS HERE

echo "
********************************************************************************

RAREFIED TABLE PROCESSING STARTS HERE

********************************************************************************
" >> $log

	echo "
Processing rarefied table."
	echo "
Processing rarefied table." >> $log

## Produce summary plots first through phyloseq (in parallel)



## Summarize taxa (yields relative abundance tables)
	if [[ ! -d $outdir/Rarefied_output/beta_diversity/summarized_tables ]]; then
	echo "
Summarize taxa command:
	summarize_taxa.py -i $raresort -o $outdir/Rarefied_output/beta_diversity/summarized_tables -L 2,3,4,5,6,7" >> $log
	echo "
Summarizing taxonomy by sample and building plots."
	summarize_taxa.py -i $raresort -o $outdir/Rarefied_output/beta_diversity/summarized_tables -L 2,3,4,5,6,7 1> $stdout 2> $stderr
	bash $scriptdir/log_slave.sh $stdout $stderr $log
	
	else
	echo "
Relative abundance tables already present." >> $log
	fi
	wait

## Beta diversity
	if [[ "$phylogenetic" == "YES" ]]; then
	if [[ ! -f $outdir/Rarefied_output/beta_diversity/bray_curtis_dm.txt && ! -f $outdir/Rarefied_output/beta_diversity/chord_dm.txt && ! -f $outdir/Rarefied_output/beta_diversity/hellinger_dm.txt && ! -f $outdir/Rarefied_output/beta_diversity/kulczynski_dm.txt && ! -f $outdir/Rarefied_output/beta_diversity/unweighted_unifrac_dm.txt && ! -f $outdir/Rarefied_output/beta_diversity/weighted_unifrac_dm.txt ]]; then
	echo "
Parallel beta diversity command:
	parallel_beta_diversity.py -i $raresort -o $outdir/Rarefied_output/beta_diversity/ --metrics $metrics -T  -t $tree --jobs_to_start $cores" >> $log
	echo "
Calculating beta diversity distance matrices."
	parallel_beta_diversity.py -i $raresort -o $outdir/Rarefied_output/beta_diversity/ --metrics $metrics -T  -t $tree --jobs_to_start $cores 1> $stdout 2> $stderr
	bash $scriptdir/log_slave.sh $stdout $stderr $log
	fi
	elif [[ "$phylogenetic" == "NO" ]]; then
	if [[ ! -f $outdir/Rarefied_output/beta_diversity/bray_curtis_dm.txt && ! -f $outdir/Rarefied_output/beta_diversity/chord_dm.txt && ! -f $outdir/Rarefied_output/beta_diversity/hellinger_dm.txt && ! -f $outdir/Rarefied_output/beta_diversity/kulczynski_dm.txt ]]; then
	echo "
Parallel beta diversity command:
	parallel_beta_diversity.py -i $raresort -o $outdir/Rarefied_output/beta_diversity/ --metrics $metrics -T --jobs_to_start $cores" >> $log
	echo "
Calculating beta diversity distance matrices."
	parallel_beta_diversity.py -i $raresort -o $outdir/Rarefied_output/beta_diversity/ --metrics $metrics -T --jobs_to_start $cores 1> $stdout 2> $stderr
	bash $scriptdir/log_slave.sh $stdout $stderr $log
	fi
	else
	echo "
Beta diversity matrices already present." >> $log
	fi
	wait

## Rename output files
	if [[ ! -f $outdir/Rarefied_output/beta_diversity/bray_curtis_dm.txt ]]; then
	bcdm=$(ls $outdir/Rarefied_output/beta_diversity/bray_curtis_rarefied_table_sorted.txt)
	mv $bcdm $outdir/Rarefied_output/beta_diversity/bray_curtis_dm.txt 2>/dev/null
	fi
	wait
	if [[ ! -f $outdir/Rarefied_output/beta_diversity/chord_dm.txt ]]; then
	cdm=$(ls $outdir/Rarefied_output/beta_diversity/chord_rarefied_table_sorted.txt)
	mv $cdm $outdir/Rarefied_output/beta_diversity/chord_dm.txt 2>/dev/null
	fi
	wait
	if [[ ! -f $outdir/Rarefied_output/beta_diversity/hellinger_dm.txt ]]; then
	hdm=$(ls $outdir/Rarefied_output/beta_diversity/hellinger_rarefied_table_sorted.txt)
	mv $hdm $outdir/Rarefied_output/beta_diversity/hellinger_dm.txt 2>/dev/null
	fi
	wait
	if [[ ! -f $outdir/Rarefied_output/beta_diversity/kulczynski_dm.txt ]]; then
	kdm=$(ls $outdir/Rarefied_output/beta_diversity/kulczynski_rarefied_table_sorted.txt)
	mv $kdm $outdir/Rarefied_output/beta_diversity/kulczynski_dm.txt 2>/dev/null
	fi
	wait
	if [[ "$phylogenetic" == "YES" ]]; then
	if [[ ! -f $outdir/Rarefied_output/beta_diversity/unweighted_unifrac_dm.txt ]]; then
	uudm=$(ls $outdir/Rarefied_output/beta_diversity/unweighted_unifrac_rarefied_table_sorted.txt)
	mv $uudm $outdir/Rarefied_output/beta_diversity/unweighted_unifrac_dm.txt 2>/dev/null
	fi
	wait
	if [[ ! -f $outdir/Rarefied_output/beta_diversity/weighted_unifrac_dm.txt ]]; then
	wudm=$(ls $outdir/Rarefied_output/beta_diversity/weighted_unifrac_rarefied_table_sorted.txt)
	mv $wudm $outdir/Rarefied_output/beta_diversity/weighted_unifrac_dm.txt 2>/dev/null
	fi
	wait
	fi
	wait

## Principal coordinates and NMDS commands
	pcoacoordscount=`ls $outdir/Rarefied_output/beta_diversity/*_pc.txt 2>/dev/null | wc -l`
	nmdscoordscount=`ls $outdir/Rarefied_output/beta_diversity/*_nmds.txt 2>/dev/null | wc -l`
	nmdsconvertcoordscount=`ls $outdir/Rarefied_output/beta_diversity/*_nmds_converted.txt 2>/dev/null | wc -l`
	if [[ $pcoacoordscount == 0 && $nmdscoordscount == 0 && $nmdsconvertcoordscount == 0 ]]; then
	echo "
Principal coordinates and NMDS commands." >> $log
	echo "
Constructing PCoA and NMDS coordinate files."
	echo "Principal coordinates:" >> $log
	for dm in $outdir/Rarefied_output/beta_diversity/*_dm.txt; do
	dmbase=$(basename $dm _dm.txt)
	echo "	principal_coordinates.py -i $dm -o $outdir/Rarefied_output/beta_diversity/${dmbase}_pc.txt" >> $log
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	( principal_coordinates.py -i $dm -o $outdir/Rarefied_output/beta_diversity/${dmbase}_pc.txt >/dev/null 2>&1 || true ) &
	done
	wait
	echo "" >> $log

	echo "NMDS coordinates:" >> $log
	for dm in $outdir/Rarefied_output/beta_diversity/*_dm.txt; do
	dmbase=$(basename $dm _dm.txt)
	echo "	nmds.py -i $dm -o $outdir/Rarefied_output/beta_diversity/${dmbase}_nmds.txt" >> $log
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	( nmds.py -i $dm -o $outdir/Rarefied_output/beta_diversity/${dmbase}_nmds.txt >/dev/null 2>&1 || true ) &
	done
	wait
	echo "" >> $log

	echo "Convert NMDS coordinates:" >> $log
	for dm in $outdir/Rarefied_output/beta_diversity/*_dm.txt; do
	dmbase=$(basename $dm _dm.txt)
	echo "	python $scriptdir/convert_nmds_coords.py -i $outdir/Rarefied_output/beta_diversity/${dmbase}_nmds.txt -o $outdir/Rarefied_output/beta_diversity/${dmbase}_nmds_converted.txt" >> $log
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	( python $scriptdir/convert_nmds_coords.py -i $outdir/Rarefied_output/beta_diversity/${dmbase}_nmds.txt -o $outdir/Rarefied_output/beta_diversity/${dmbase}_nmds_converted.txt >/dev/null 2>&1 || true ) &
	done
	wait
	echo "" >> $log
	else
	echo "
PCoA and NMDS coordinate files already present." >> $log
	fi

## Make 3D emperor plots (PCoA)
	pcoaplotscount=`ls $outdir/Rarefied_output/beta_diversity/*_pcoa_plot 2>/dev/null | wc -l`
	if [[ $pcoaplotscount == 0 ]]; then
	echo "
Make emperor commands:" >> $log
	echo "
Generating 3D PCoA plots."
	echo "PCoA plots:" >> $log
	for pc in $outdir/Rarefied_output/beta_diversity/*_pc.txt; do
	pcbase=$(basename $pc _pc.txt)
		if [[ -d $outdir/Rarefied_output/beta_diversity/${pcbase}_emperor_pcoa_plot/ ]]; then
		rm -r $outdir/Rarefied_output/beta_diversity/${pcbase}_emperor_pcoa_plot/
		fi
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	echo "	make_emperor.py -i $pc -o $outdir/Rarefied_output/beta_diversity/${pcbase}_emperor_pcoa_plot/ -m $mapfile --add_unique_columns --ignore_missing_samples" >> $log
	( make_emperor.py -i $pc -o $outdir/Rarefied_output/beta_diversity/${pcbase}_emperor_pcoa_plot/ -m $mapfile --add_unique_columns --ignore_missing_samples >/dev/null 2>&1 || true ) &
	done
	wait
	echo "" >> $log
	else
	echo "
3D PCoA plots already present." >> $log
	fi

## Make 3D emperor plots (NMDS)
	nmdsplotscount=`ls $outdir/Rarefied_output/beta_diversity/*_nmds_plot 2>/dev/null | wc -l`
	if [[ $nmdsplotscount == 0 ]]; then
	echo "
Generating 3D NMDS plots."
	echo "NMDS plots:" >> $log
	for nmds in $outdir/Rarefied_output/beta_diversity/*_nmds_converted.txt; do
	nmdsbase=$(basename $nmds _nmds_converted.txt)
		if [[ -d $outdir/Rarefied_output/beta_diversity/${nmdsbase}_emperor_nmds_plot/ ]]; then
		rm -r $outdir/Rarefied_output/beta_diversity/${nmdsbase}_emperor_nmds_plot/
		fi
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	echo "	make_emperor.py -i $nmds -o $outdir/Rarefied_output/beta_diversity/${nmdsbase}_emperor_nmds_plot/ -m $mapfile --add_unique_columns --ignore_missing_samples" >> $log
	( make_emperor.py -i $nmds -o $outdir/Rarefied_output/beta_diversity/${nmdsbase}_emperor_nmds_plot/ -m $mapfile --add_unique_columns --ignore_missing_samples >/dev/null 2>&1 || true ) &
	done
	wait
	echo "" >> $log
	else
	echo "
3D NMDS plots already present." >> $log
	fi

	## Update HTML output
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

## Make 2D plots
	if [[ ! -d $outdir/Rarefied_output/beta_diversity/2D_PCoA_bdiv_plots ]]; then
	echo "
Make 2D PCoA plots commands:" >> $log
	echo "
Generating 2D PCoA plots."
	for pc in $outdir/Rarefied_output/beta_diversity/*_pc.txt; do
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	echo "	make_2d_plots.py -i $pc -m $mapfile -o $outdir/Rarefied_output/beta_diversity/2D_PCoA_bdiv_plots" >> $log
	( make_2d_plots.py -i $pc -m $mapfile -o $outdir/Rarefied_output/beta_diversity/2D_PCoA_bdiv_plots >/dev/null 2>&1 || true ) &
	done
	wait
	echo "" >> $log
	else
	echo "
2D plots already present." >> $log
	fi

	## Update HTML output
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

## Comparing categories statistics
if [[ ! -f $outdir/Rarefied_output/beta_diversity/permanova_results_collated.txt && ! -f $outdir/Rarefied_output/beta_diversity/permdisp_results_collated.txt && ! -f $outdir/Rarefied_output/beta_diversity/anosim_results_collated.txt && ! -f $outdir/Rarefied_output/beta_diversity/dbrda_results_collated.txt && ! -f $outdir/Rarefied_output/beta_diversity/adonis_results_collated.txt ]]; then
echo "
Compare categories commands:" >> $log
	echo "
Calculating one-way statsitics from distance matrices."
	if [[ ! -f $outdir/Rarefied_output/beta_diversity/permanova_results_collated.txt ]]; then
echo > $outdir/Rarefied_output/beta_diversity/permanova_results_collated.txt
echo "Running PERMANOVA tests."
echo "PERMANOVA:" >> $log
	for line in `cat $catlist`; do
		for dm in $outdir/Rarefied_output/beta_diversity/*_dm.txt; do
		method=$(basename $dm _dm.txt)
		while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
		sleep 1
		done
		echo "	compare_categories.py --method permanova -i $dm -m $mapfile -c $line -o $outdir/Rarefied_output/beta_diversity/permanova_out/$line/$method/" >> $log
		( compare_categories.py --method permanova -i $dm -m $mapfile -c $line -o $outdir/Rarefied_output/beta_diversity/permanova_out/$line/$method/ >/dev/null 2>&1 || true ) &
		done
	done
	wait
	echo "" >> $log

	for line in `cat $catlist`; do
		for dm in $outdir/Rarefied_output/beta_diversity/*_dm.txt; do
		method=$(basename $dm _dm.txt)
		echo "Category: $line" >> $outdir/Rarefied_output/beta_diversity/permanova_results_collated.txt
		echo "Method: $method" >> $outdir/Rarefied_output/beta_diversity/permanova_results_collated.txt
		cat $outdir/Rarefied_output/beta_diversity/permanova_out/$line/$method/permanova_results.txt >> $outdir/Rarefied_output/beta_diversity/permanova_results_collated.txt 2>/dev/null || true
		echo "" >> $outdir/Rarefied_output/beta_diversity/permanova_results_collated.txt
		done
	done
	wait
	fi

	if [[ ! -f $outdir/Rarefied_output/beta_diversity/permdisp_results_collated.txt ]]; then
echo > $outdir/Rarefied_output/beta_diversity/permdisp_results_collated.txt
echo "Running PERMDISP tests."
echo "PERMDISP:" >> $log
	for line in `cat $catlist`; do
		for dm in $outdir/Rarefied_output/beta_diversity/*_dm.txt; do
		method=$(basename $dm _dm.txt)
		while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
		sleep 1
		done
		echo "	compare_categories.py --method permdisp -i $dm -m $mapfile -c $line -o $outdir/Rarefied_output/beta_diversity/permdisp_out/$line/$method/" >> $log
		( compare_categories.py --method permdisp -i $dm -m $mapfile -c $line -o $outdir/Rarefied_output/beta_diversity/permdisp_out/$line/$method/ >/dev/null 2>&1 || true ) &
		done
	done
	wait
	echo "" >> $log

	for line in `cat $catlist`; do
		for dm in $outdir/Rarefied_output/beta_diversity/*_dm.txt; do
		method=$(basename $dm _dm.txt)
		echo "Category: $line" >> $outdir/Rarefied_output/beta_diversity/permdisp_results_collated.txt
		echo "Method: $method" >> $outdir/Rarefied_output/beta_diversity/permdisp_results_collated.txt
		cat $outdir/Rarefied_output/beta_diversity/permdisp_out/$line/$method/permdisp_results.txt >> $outdir/Rarefied_output/beta_diversity/permdisp_results_collated.txt 2>/dev/null || true
		echo "" >> $outdir/Rarefied_output/beta_diversity/permdisp_results_collated.txt
		done
	done
	wait
	fi

	if [[ ! -f $outdir/Rarefied_output/beta_diversity/anosim_results_collated.txt ]]; then
echo > $outdir/Rarefied_output/beta_diversity/anosim_results_collated.txt
echo "Running ANOSIM tests."
echo "ANOSIM:" >> $log
	for line in `cat $catlist`; do
		for dm in $outdir/Rarefied_output/beta_diversity/*_dm.txt; do
		method=$(basename $dm _dm.txt)
		while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
		sleep 1
		done
		echo "	compare_categories.py --method anosim -i $dm -m $mapfile -c $line -o $outdir/Rarefied_output/beta_diversity/anosim_out/$line/$method/" >> $log
		( compare_categories.py --method anosim -i $dm -m $mapfile -c $line -o $outdir/Rarefied_output/beta_diversity/anosim_out/$line/$method/ 2>/dev/null 2>&1 || true ) &
		done
	done
	wait
	echo "" >> $log

	for line in `cat $catlist`; do
		for dm in $outdir/Rarefied_output/beta_diversity/*_dm.txt; do
		method=$(basename $dm _dm.txt)
		echo "Category: $line" >> $outdir/Rarefied_output/beta_diversity/anosim_results_collated.txt
		echo "Method: $method" >> $outdir/Rarefied_output/beta_diversity/anosim_results_collated.txt
		cat $outdir/Rarefied_output/beta_diversity/anosim_out/$line/$method/anosim_results.txt >> $outdir/Rarefied_output/beta_diversity/anosim_results_collated.txt 2>/dev/null || true
		echo "" >> $outdir/Rarefied_output/beta_diversity/anosim_results_collated.txt
		done
	done
	wait
	fi

	if [[ ! -f $outdir/Rarefied_output/beta_diversity/dbrda_results_collated.txt ]]; then
echo > $outdir/Rarefied_output/beta_diversity/dbrda_results_collated.txt
echo "Running DB-RDA tests."
echo "DB-RDA:" >> $log
	for line in `cat $catlist`; do
		for dm in $outdir/Rarefied_output/beta_diversity/*_dm.txt; do
		method=$(basename $dm _dm.txt)
		while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
		sleep 1
		done
		echo "	compare_categories.py --method dbrda -i $dm -m $mapfile -c $line -o $outdir/Rarefied_output/beta_diversity/dbrda_out/$line/$method/" >> $log
		( compare_categories.py --method dbrda -i $dm -m $mapfile -c $line -o $outdir/Rarefied_output/beta_diversity/dbrda_out/$line/$method/ 2>/dev/null 2>&1 || true ) &
		done
	done
	wait
	echo "" >> $log

	for line in `cat $catlist`; do
		for dm in $outdir/Rarefied_output/beta_diversity/*_dm.txt; do
		method=$(basename $dm _dm.txt)
		echo "Category: $line" >> $outdir/Rarefied_output/beta_diversity/dbrda_results_collated.txt
		echo "Method: $method" >> $outdir/Rarefied_output/beta_diversity/dbrda_results_collated.txt
		cat $outdir/Rarefied_output/beta_diversity/dbrda_out/$line/$method/dbrda_results.txt >> $outdir/Rarefied_output/beta_diversity/dbrda_results_collated.txt 2>/dev/null || true
		echo "" >> $outdir/Rarefied_output/beta_diversity/dbrda_results_collated.txt
		done
	done
	wait
	fi

	if [[ ! -f $outdir/Rarefied_output/beta_diversity/adonis_results_collated.txt ]]; then
echo > $outdir/Rarefied_output/beta_diversity/adonis_results_collated.txt
echo "Running Adonis tests."
echo "Adonis:" >> $log
	for line in `cat $catlist`; do
		for dm in $outdir/Rarefied_output/beta_diversity/*_dm.txt; do
		method=$(basename $dm _dm.txt)
		while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
		sleep 1
		done
		echo "	compare_categories.py --method adonis -i $dm -m $mapfile -c $line -o $outdir/Rarefied_output/beta_diversity/adonis_out/$line/$method/" >> $log
		( compare_categories.py --method adonis -i $dm -m $mapfile -c $line -o $outdir/Rarefied_output/beta_diversity/adonis_out/$line/$method/ 2>/dev/null 2>&1 || true ) &
		done
	done
	wait
	echo "" >> $log

	for line in `cat $catlist`; do
		for dm in $outdir/Rarefied_output/beta_diversity/*_dm.txt; do
		method=$(basename $dm _dm.txt)
		echo "Category: $line" >> $outdir/Rarefied_output/beta_diversity/adonis_results_collated.txt
		echo "Method: $method" >> $outdir/Rarefied_output/beta_diversity/adonis_results_collated.txt
		cat $outdir/Rarefied_output/beta_diversity/adonis_out/$line/$method/adonis_results.txt >> $outdir/Rarefied_output/beta_diversity/adonis_results_collated.txt 2>/dev/null || true
		echo "" >> $outdir/Rarefied_output/beta_diversity/adonis_results_collated.txt
		done
	done
	wait
	fi
else
echo "
Categorical comparisons already present." >> $log
fi
	## Update HTML output
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

## Distance boxplots for each category
	boxplotscount=`ls $outdir/Rarefied_output/beta_diversity/*_boxplots 2>/dev/null | wc -l`
	if [[ $boxplotscount == 0 ]]; then
	echo "
Make distance boxplots commands:" >> $log
	echo "
Generating distance boxplots."
	for line in `cat $catlist`; do
		for dm in $outdir/Rarefied_output/beta_diversity/*_dm.txt; do
		dmbase=$(basename $dm _dm.txt)
		while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
		sleep 1
		done
		echo "	make_distance_boxplots.py -d $outdir/Rarefied_output/beta_diversity/${dmbase}_dm.txt -f $line -o $outdir/Rarefied_output/beta_diversity/${dmbase}_boxplots/ -m $mapfile -n 999" >> $log
		( make_distance_boxplots.py -d $outdir/Rarefied_output/beta_diversity/${dmbase}_dm.txt -f $line -o $outdir/Rarefied_output/beta_diversity/${dmbase}_boxplots/ -m $mapfile -n 999 >/dev/null 2>&1 || true ) &
		done
	done
	wait
	echo "" >> $log
	else
	echo "
Boxplots already present." >> $log
	fi

	## Update HTML output
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

## Make biplots
	if [[ ! -d $outdir/Rarefied_output/beta_diversity/biplots ]]; then
	echo "
Make biplots commands:" >> $log
	echo "
Generating PCoA biplots."
	mkdir $outdir/Rarefied_output/beta_diversity/biplots
	for pc in $outdir/Rarefied_output/beta_diversity/*_pc.txt; do
	pcmethod=$(basename $pc _pc.txt)
	mkdir $outdir/Rarefied_output/beta_diversity/biplots/$pcmethod
	done
	wait

	for pc in $outdir/Rarefied_output/beta_diversity/*_pc.txt; do
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	pcmethod=$(basename $pc _pc.txt)
		for level in $outdir/Rarefied_output/beta_diversity/summarized_tables/rarefied_table_sorted_*.txt; do
		L=$(basename $level .txt)
		echo "	make_emperor.py -i $pc -m $mapfile -o $outdir/Rarefied_output/beta_diversity/biplots/$pcmethod/$L -t $level --add_unique_columns --ignore_missing_samples" >> $log
		( make_emperor.py -i $pc -m $mapfile -o $outdir/Rarefied_output/beta_diversity/biplots/$pcmethod/$L -t $level --add_unique_columns --ignore_missing_samples >/dev/null 2>&1 || true ) &
		done
	done
	wait
	echo "" >> $log
	else
	echo "
Biplots already present." >> $log
	fi

	## Update HTML output
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

## Run supervised learning on data using supplied categories
	if [[ ! -d $outdir/Rarefied_output/SupervisedLearning ]]; then
	mkdir -p $outdir/Rarefied_output/SupervisedLearning
	echo "
Supervised learning commands:" >> $log
	echo "
Running supervised learning analysis."
	for category in `cat $catlist`; do
		while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
		sleep 1
		done
		echo "	supervised_learning.py -i $raresort -m $mapfile -c $category -o $outdir/Rarefied_output/SupervisedLearning/$category --ntree 1000" >> $log
		( supervised_learning.py -i $raresort -m $mapfile -c $category -o $outdir/Rarefied_output/SupervisedLearning/$category --ntree 1000 &>/dev/null 2>&1 || true ) &
	done
	else
	echo "
Supervised Learning already present." >> $log
	fi

	## Update HTML output
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

## Make rank abundance plots (rarefied)
	if [[ ! -d $outdir/Rarefied_output/RankAbundance ]]; then
	mkdir $outdir/Rarefied_output/RankAbundance
	echo "
Rank abundance plot commands:" >> $log
	echo "
Generating rank abundance plots."
	echo "	plot_rank_abundance_graph.py -i $raresort -o $outdir/Rarefied_output/RankAbundance/rankabund_xlog-ylog.pdf -s "*" -n
	plot_rank_abundance_graph.py -i $raresort -o $outdir/Rarefied_output/RankAbundance/rankabund_xlinear-ylog.pdf -s "*" -n -x
	plot_rank_abundance_graph.py -i $raresort -o $outdir/Rarefied_output/RankAbundance/rankabund_xlog-ylinear.pdf -s "*" -n -y
	plot_rank_abundance_graph.py -i $raresort -o $outdir/Rarefied_output/RankAbundance/rankabund_xlinear-ylinear.pdf -s "*" -n -x -y
	" >> $log
	( plot_rank_abundance_graph.py -i $raresort -o $outdir/Rarefied_output/RankAbundance/rankabund_xlog-ylog.pdf -s "*" -n ) &
	( plot_rank_abundance_graph.py -i $raresort -o $outdir/Rarefied_output/RankAbundance/rankabund_xlinear-ylog.pdf -s "*" -n -x ) &
	( plot_rank_abundance_graph.py -i $raresort -o $outdir/Rarefied_output/RankAbundance/rankabund_xlog-ylinear.pdf -s "*" -n -y ) &
	( plot_rank_abundance_graph.py -i $raresort -o $outdir/Rarefied_output/RankAbundance/rankabund_xlinear-ylinear.pdf -s "*" -n -x -y ) &
	fi
wait

	## Update HTML output
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

	## Remove pointless log.txt file output by supervised learning
	sllogtest=$(grep "confusion.matrix" ./log.txt 2>/dev/null)
	if [[ ! -z "$sllogtest" ]]; then
		rm log.txt
	fi

###################################
## Start of alpha diversity steps

## Multiple rarefactions
	alphastepsize=$(($depth/10))
	alphaout="$outdir/Alpha_diversity_max$depth"

	if [[ ! -d $alphaout ]]; then
	echo "
Multiple rarefaction command:
	parallel_multiple_rarefactions.py -T -i $raresort -m 10 -x $depth -s $alphastepsize -o $alphaout/rarefaction/ -O $cores" >> $log
	echo "
Performing mutiple rarefactions for alpha diversity analysis."
	parallel_multiple_rarefactions.py -T -i $raresort -m 10 -x $depth -s $alphastepsize -o $alphaout/rarefaction/ -O $cores 1> $stdout 2> $stderr
	wait
	bash $scriptdir/log_slave.sh $stdout $stderr $log

## Alpha diversity
	if [[ "$phylogenetic" == "YES" ]]; then
	echo "
Alpha diversity command:
	parallel_alpha_diversity.py -T -i $alphaout/rarefaction/ -o $alphaout/alpha_div/ -t $tree -O $cores -m $alphametrics" >> $log
	echo "
Calculating alpha diversity."
	parallel_alpha_diversity.py -T -i $alphaout/rarefaction/ -o $alphaout/alpha_div/ -t $tree -O $cores -m $alphametrics
        elif [[ "$phylogenetic" == "NO" ]]; then
	echo "
Alpha diversity command:
        parallel_alpha_diversity.py -T -i $alphaout/rarefaction/ -o $alphaout/alpha_div/ -O $cores -m $alphametrics" >> $log
	echo "
Calculating alpha diversity."
        parallel_alpha_diversity.py -T -i $alphaout/rarefaction/ -o $alphaout/alpha_div/ -O $cores -m $alphametrics
	fi

## Collate alpha
	if [[ ! -d alphaout/alpha_div_collated/ ]]; then
	echo "
Collate alpha command:
	collate_alpha.py -i $alphaout/alpha_div/ -o $alphaout/alpha_div_collated/" >> $log
	collate_alpha.py -i $alphaout/alpha_div/ -o $alphaout/alpha_div_collated/ 1> $stdout 2> $stderr
	wait
	bash $scriptdir/log_slave.sh $stdout $stderr $log
	rm -r $alphaout/rarefaction/ $alphaout/alpha_div/

## Make rarefaction plots
	echo "
Make rarefaction plots command:
	make_rarefaction_plots.py -i $alphaout/alpha_div_collated/ -m $mapfile -o $alphaout/alpha_rarefaction_plots/ -d 300 -e stderr" >> $log
	echo "
Generating alpha rarefaction plots."
	make_rarefaction_plots.py -i $alphaout/alpha_div_collated/ -m $mapfile -o $alphaout/alpha_rarefaction_plots/ -d 300 -e stderr 1> $stdout 2> $stderr || true
	wait
	bash $scriptdir/log_slave.sh $stdout $stderr $log

## Alpha diversity stats
	echo "
Compare alpha diversity commands:" >> $log
	echo "
Calculating alpha diversity statistics."
	for file in $alphaout/alpha_div_collated/*.txt; do
	filebase=$(basename $file .txt)
		while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
		sleep 1
		done
		echo "compare_alpha_diversity.py -i $file -m $mapfile -c $cats -o $alphaout/alpha_compare_parametric -t parametric -p fdr" >> $log
		( compare_alpha_diversity.py -i $file -m $mapfile -c $cats -o $alphaout/compare_$filebase\_parametric -t parametric -p fdr >/dev/null 2>&1 || true ) &
		echo "compare_alpha_diversity.py -i $file -m $mapfile -c $cats -o $alphaout/alpha_compare_nonparametric -t nonparametric -p fdr" >> $log
		( compare_alpha_diversity.py -i $file -m $mapfile -c $cats -o $alphaout/compare_$filebase\_nonparametric -t nonparametric -p fdr >/dev/null 2>&1 || true ) &
	done
	fi
	wait
	else
	echo "
Alpha diversity analysis already completed." >> $log
	fi

	## Update HTML output
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

#######################################
## Start of taxonomy plotting steps

## Plot taxa summaries
		taxaout="$outdir/Rarefied_output/taxa_plots"
		if [[ ! -d $taxaout ]]; then
	echo "
Plotting taxonomy by sample."
	echo "
Plot taxa summaries command:
	plot_taxa_summary.py -i $outdir/Rarefied_output/beta_diversity/summarized_tables/rarefied_table_sorted_L2.txt,$outdir/Rarefied_output/beta_diversity/summarized_tables/rarefied_table_sorted_L3.txt,$outdir/Rarefied_output/beta_diversity/summarized_tables/rarefied_table_sorted_L4.txt,$outdir/Rarefied_output/beta_diversity/summarized_tables/rarefied_table_sorted_L5.txt,$outdir/Rarefied_output/beta_diversity/summarized_tables/rarefied_table_sorted_L6.txt,$outdir/Rarefied_output/beta_diversity/summarized_tables/rarefied_table_sorted_L7.txt -o $taxaout/taxa_summary_plots/ -c bar" >> $log
	plot_taxa_summary.py -i $outdir/Rarefied_output/beta_diversity/summarized_tables/rarefied_table_sorted_L2.txt,$outdir/Rarefied_output/beta_diversity/summarized_tables/rarefied_table_sorted_L3.txt,$outdir/Rarefied_output/beta_diversity/summarized_tables/rarefied_table_sorted_L4.txt,$outdir/Rarefied_output/beta_diversity/summarized_tables/rarefied_table_sorted_L5.txt,$outdir/Rarefied_output/beta_diversity/summarized_tables/rarefied_table_sorted_L6.txt,$outdir/Rarefied_output/beta_diversity/summarized_tables/rarefied_table_sorted_L7.txt -o $taxaout/taxa_summary_plots/ -c bar -l Phylum,Class,Order,Family,Genus,Species 1> $stdout 2> $stderr || true
	wait
		bash $scriptdir/log_slave.sh $stdout $stderr $log
		fi

## Taxa summaries for each category
	for line in `cat $catlist`; do
		taxaout="$outdir/Rarefied_output/taxa_plots_${line}"
		if [[ ! -d $taxaout ]]; then
	echo "
Building taxonomy plots for category: $line."
	echo "
Summarize taxa commands by category \"$line\":
	collapse_samples.py -m ${mapfile} -b ${raresort} --output_biom_fp ${taxaout}/${line}_otu_table.biom --output_mapping_fp ${taxaout}/${line}_map.txt --collapse_fields $line
	sort_otu_table.py -i ${taxaout}/${line}_otu_table.biom -o ${taxaout}/${line}_otu_table_sorted.biom
	summarize_taxa.py -i ${taxaout}/${line}_otu_table_sorted.biom -o ${taxaout}/  -L 2,3,4,5,6,7 -a
	plot_taxa_summary.py -i ${taxaout}/${line}_otu_table_sorted_L2.txt,${taxaout}/${line}_otu_table_sorted_L3.txt,${taxaout}/${line}_otu_table_sorted_L4.txt,${taxaout}/${line}_otu_table_sorted_L5.txt,${taxaout}/${line}_otu_table_sorted_L6.txt,${taxaout}/${line}_otu_table_sorted_L7.txt -o ${taxaout}/taxa_summary_plots/ -c bar,pie" >> $log

		mkdir $taxaout

	collapse_samples.py -m ${mapfile} -b ${raresort} --output_biom_fp ${taxaout}/${line}_otu_table.biom --output_mapping_fp ${taxaout}/${line}_map.txt --collapse_fields $line 1> $stdout 2> $stderr || true
	wait
		bash $scriptdir/log_slave.sh $stdout $stderr $log
		wait
	sort_otu_table.py -i ${taxaout}/${line}_otu_table.biom -o ${taxaout}/${line}_otu_table_sorted.biom 1> $stdout 2> $stderr || true
	wait
		bash $scriptdir/log_slave.sh $stdout $stderr $log
		wait
	summarize_taxa.py -i ${taxaout}/${line}_otu_table_sorted.biom -o ${taxaout}/  -L 2,3,4,5,6,7 -a 1> $stdout 2> $stderr || true
	wait
		bash $scriptdir/log_slave.sh $stdout $stderr $log
		wait
	plot_taxa_summary.py -i ${taxaout}/${line}_otu_table_sorted_L2.txt,${taxaout}/${line}_otu_table_sorted_L3.txt,${taxaout}/${line}_otu_table_sorted_L4.txt,${taxaout}/${line}_otu_table_sorted_L5.txt,${taxaout}/${line}_otu_table_sorted_L6.txt,${taxaout}/${line}_otu_table_sorted_L7.txt -o ${taxaout}/taxa_summary_plots/ -c bar,pie -l Phylum,Class,Order,Family,Genus,Species -d 300 -w 0.65 -x 8 -y 10 1> $stdout 2> $stderr || true
	wait
		bash $scriptdir/log_slave.sh $stdout $stderr $log
		wait
		fi
	done

	## Update HTML output
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

############################
## Group comparison steps

## Group significance for each category (Kruskal-Wallis and nonparametric Ttest)

	## Kruskal-Wallis
	kwout="$outdir/Rarefied_output/KruskalWallis/"
	kwtestcount=$(ls $kwout/kruskalwallis_* 2> /dev/null | wc -l)
	if [[ $kwtestcount == 0 ]]; then
	echo "
Group significance commands:" >> $log
	if [[ ! -d $kwout ]]; then
	mkdir $kwout
	fi
	raresortrel="$outdir/OTU_tables/rarefied_table_sorted_relativized.biom"
	if [[ ! -f $raresortrel ]]; then
	echo "
Relativizing OTU table:
	relativize_otu_table.py -i $raresort" >> $log
	relativize_otu_table.py -i $raresort >/dev/null 2>&1 || true
	fi
		raresortreltxt="$outdir/OTU_tables/rarefied_table_sorted_relativized.txt"
		if [[ ! -f $raresortreltxt ]]; then
		biomtotxt.sh $raresortrel &>/dev/null
		fi
	echo "
Calculating Kruskal-Wallis test statistics when possible."
for line in `cat $catlist`; do
	if [[ ! -f $kwout/kruskalwallis_${line}_OTU.txt ]]; then
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	echo "	group_significance.py -i $raresortrel -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_OTU.txt -s kruskal_wallis" >> $log
	( group_significance.py -i $raresortrel -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_OTU.txt -s kruskal_wallis ) >/dev/null 2>&1 || true &
	fi
done
wait
for line in `cat $catlist`; do
	if [[ ! -f $kwout/kruskalwallis_$line\_L2.txt ]]; then
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	echo "	group_significance.py -i $outdir/Rarefied_output/beta_diversity/summarized_tables/rarefied_table_sorted_L2.biom -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_L2.txt -s kruskal_wallis" >> $log
	( group_significance.py -i $outdir/Rarefied_output/beta_diversity/summarized_tables/rarefied_table_sorted_L2.biom -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_L2.txt -s kruskal_wallis ) >/dev/null 2>&1 || true &
	fi
done
wait
for line in `cat $catlist`; do
	if [[ ! -f $kwout/kruskalwallis_$line\_L3.txt ]]; then
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	echo "	group_significance.py -i $outdir/Rarefied_output/beta_diversity/summarized_tables/rarefied_table_sorted_L3.biom -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_L3.txt -s kruskal_wallis" >> $log
	( group_significance.py -i $outdir/Rarefied_output/beta_diversity/summarized_tables/rarefied_table_sorted_L3.biom -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_L3.txt -s kruskal_wallis ) >/dev/null 2>&1 || true &
	fi
done
wait
for line in `cat $catlist`; do
	if [[ ! -f $kwout/kruskalwallis_$line\_L4.txt ]]; then
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	echo "	group_significance.py -i $outdir/Rarefied_output/beta_diversity/summarized_tables/rarefied_table_sorted_L4.biom -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_L4.txt -s kruskal_wallis" >> $log
	( group_significance.py -i $outdir/Rarefied_output/beta_diversity/summarized_tables/rarefied_table_sorted_L4.biom -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_L4.txt -s kruskal_wallis ) >/dev/null 2>&1 || true &
	fi
done
wait
for line in `cat $catlist`; do
	if [[ ! -f $kwout/kruskalwallis_$line\_L5.txt ]]; then
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	echo "	group_significance.py -i $outdir/Rarefied_output/beta_diversity/summarized_tables/rarefied_table_sorted_L5.biom -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_L5.txt -s kruskal_wallis" >> $log
	( group_significance.py -i $outdir/Rarefied_output/beta_diversity/summarized_tables/rarefied_table_sorted_L5.biom -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_L5.txt -s kruskal_wallis ) >/dev/null 2>&1 || true &
	fi
done
wait
for line in `cat $catlist`; do
	if [[ ! -f $kwout/kruskalwallis_$line\_L6.txt ]]; then
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	echo "	group_significance.py -i $outdir/Rarefied_output/beta_diversity/summarized_tables/rarefied_table_sorted_L6.biom -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_L6.txt -s kruskal_wallis" >> $log
	( group_significance.py -i $outdir/Rarefied_output/beta_diversity/summarized_tables/rarefied_table_sorted_L6.biom -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_L6.txt -s kruskal_wallis ) >/dev/null 2>&1 || true &
	fi
done
wait
for line in `cat $catlist`; do
	if [[ ! -f $kwout/kruskalwallis_$line\_L7.txt ]]; then
	while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
	sleep 1
	done
	echo "	group_significance.py -i $outdir/Rarefied_output/beta_diversity/summarized_tables/rarefied_table_sorted_L7.biom -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_L7.txt -s kruskal_wallis" >> $log
	( group_significance.py -i $outdir/Rarefied_output/beta_diversity/summarized_tables/rarefied_table_sorted_L7.biom -m $mapfile -c $line -o $kwout/kruskalwallis_${line}_L7.txt -s kruskal_wallis ) >/dev/null 2>&1 || true &
	fi
done
fi
wait
	## Update HTML output
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

	## Make OTU table output with absolute counts
	sumtables="$outdir/Rarefied_output/OTU_tables/"
	sumtablesabs=$(readlink -m $sumtables)
	if [[ ! -d "$sumtables" ]]; then
		mkdir -p $sumtables
	fi
	rm $sumtables/* 2>/dev/null
	if [[ -f "$outdir/OTU_tables/rarefied_table_sorted.biom" ]]; then
		cp $outdir/OTU_tables/rarefied_table_sorted.biom $sumtables

	## Summarize the sorted table and produce a list of tables to process in a variable
		summarize_taxa.py -i $sumtables/rarefied_table_sorted.biom -L 2,3,4,5,6,7 --suppress_classic_table_output -a -o $sumtables
		wait
	fi

	## Remove OTU-level table
	rm $sumtables/rarefied_table_sorted.biom

	## ANCOM
	ancomtoprocess=$(ls $sumtables 2>/dev/null)
	ancout="$outdir/Rarefied_output/ANCOM/"
	if [[ ! -d "$ancout" ]]; then
	echo "
Calculating ANCOM test statistics when possible."

	## Set up ANCOM output directory
	antestcount=$(ls $ancout/ANCOM_* 2> /dev/null | wc -l)
	if [[ $antestcount == 0 ]]; then
	echo "
ANCOM commands:" >> $log
		if [[ ! -d $ancout ]]; then
			mkdir -p $ancout
		fi
		cp $sumtables/*.biom $ancout/
		cd $ancout
#		cp $sumtablesabs/*.biom ./
		wait

	## Nested for loops to process ANCOM stats
	for line in `cat $catlist`; do
		while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
		sleep 1
		done
		for ancomtable in $ancomtoprocess; do
		echo "ancomR.sh $ancomtable $mapfileabs $line 0.05 $cores" >> $log
		ancomR.sh $ancomtable $mapfileabs $line 0.05 $cores >/dev/null 2>&1 || true &
		done
	done
	wait
	echo "" >> $log
	rm *.biom
	cd $workdir

	fi
	fi

wait

	## Indicator species analysis
	cd $workdir
	indicout="$outdir/Rarefied_output/Indicator_species/"
	if [[ ! -d "$indicout" ]]; then
	echo "
Calculating indicator species analysis test statistics when possible."

	## Set up Indicator species output directory
	indictestcount=$(ls $indicout/Indicspecies_* 2> /dev/null | wc -l)
	if [[ $indictestcount == 0 ]]; then
	echo "
Indicator species commands:" >> $log
		if [[ ! -d $indicout ]]; then
			mkdir -p $indicout
		fi
		cp $sumtables/*.biom $indicout
		cd $indicout
		wait

	## Nested for loops to process Indicator species stats
	for line in `cat $catlist`; do
		while [ $( pgrep -P $$ |wc -w ) -ge ${threads} ]; do 
		sleep 1
		done
		for indictable in $ancomtoprocess; do
		echo "indicator_species.sh $mapfileabs $indictable $line 9999" >> $log
		( indicator_species.sh $mapfileabs $indictable $line 9999 ) >/dev/null 2>&1 || true &
		done
	done
	wait
	echo "" >> $log
	rm *.biom
	cd $workdir
	fi

wait
	## Update HTML output
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase
	fi

## Run match_reads_to_taxonomy if rep set present
## Automatically find merged_rep_set.fna file from existing akutils workflows
if [[ ! -d $outdir/Representative_sequences ]]; then
	rep_set="$inputdirup1/merged_rep_set.fna"
	mkdir -p $outdir/Representative_sequences/
	cp $rep_set $outdir/Representative_sequences/

	if [[ -f $outdir/Representative_sequences/merged_rep_set.fna ]]; then
	repseqs="$outdir/Representative_sequences/merged_rep_set.fna"
	echo "
Extracting sequencing data for each taxon and performing mafft alignments.
	"
echo "
Extracting sequences command:
	bash $scriptdir/match_reads_to_taxonomy.sh $intable $threads $repseqs" >> $log
	bash $scriptdir/match_reads_to_taxonomy.sh $intable $threads $repseqs 1> $stdout 2> $stderr || true
	wait
		bash $scriptdir/log_slave.sh $stdout $stderr $log

	fi

fi
	## Update HTML output
		bash $scriptdir/html_generator.sh $inputbase $outdir $depth $catlist $alphatemp $randcode $tempdir $repodir $treebase $mapbase

done
################################################################################
## End of for loop for multiple tables processing

## Log end of workflow and exit
res1=$(date +%s.%N)
dt=$(echo "$res1 - $res0" | bc)
dd=$(echo "$dt/86400" | bc)
dt2=$(echo "$dt-86400*$dd" | bc)
dh=$(echo "$dt2/3600" | bc)
dt3=$(echo "$dt2-3600*$dh" | bc)
dm=$(echo "$dt3/60" | bc)
ds=$(echo "$dt3-60*$dm" | bc)

runtime=`printf "Total runtime: %d days %02d hours %02d minutes %02.1f seconds\n" $dd $dh $dm $ds`

echo "
akutils core_diversity steps completed.  Hooray!
Processed $tablecount OTU tables.
$runtime
"
echo "
********************************************************************************

akutils core_diversity steps completed.  Hooray!
Processed $tablecount OTU tables.
$runtime

********************************************************************************
" >> $log

exit 0
