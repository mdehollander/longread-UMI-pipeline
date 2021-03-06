#!/bin/bash
# DESCRIPTION
#    Script for processing Nanopore UMI amplicon data
#    from Zymo mock bacterial rRNA genes.
#    
# IMPLEMENTATION
#    author	Søren Karst (sorenkarst@gmail.com)
#               Ryans Ziels (ziels@mail.ubc.ca)
#    license	GNU General Public License

### Source commands and subscripts -------------------------------------
export PIPELINE_PATH="$(dirname "$(readlink -f "$0")")"
. $PIPELINE_PATH/scripts/dependencies.sh # Path to dependencies script
THREADS=${1:-60}

### Data processing -----------------------------------------------------

# Validation
mkdir validation

### Prepare binning statistics
cp umi_binning/read_binning/umi_bin_map.txt validation/
cp umi_binning/umi_ref/umi_ref.txt validation/

### Prepare read data
$SEQTK sample -s1334 reads.fq 5000 |\
  $SEQTK seq -a - \
  > validation/reads.fa

$MINIMAP2 \
  -x map-ont \
  $REF \
  umi_binning/trim/reads_tf.fq -t $THREADS |\
  $GAWK '$13 ~ /tp:A:P/{split($6,tax,"_"); print $1, tax[1]"_"tax[2]}'\
  > validation/read_classification.txt

### Prepare consensus data
cp ./consensus_sracon_medaka_medaka.fa validation/
cp ./variants/variants_all.fa validation/

### Mapping
for DATA_FILE in validation/*.fa; do
  DATA_NAME=${DATA_FILE%.*};
  DATA_NAME=${DATA_NAME##*/};
  $MINIMAP2 -ax map-ont $REF $DATA_FILE -t $THREADS --cs |\
    $SAMTOOLS view -F 2308 - |\
    cut -f1-9,12,21 > validation/$DATA_NAME.sam
done

$MINIMAP2 \
  -ax map-ont \
  validation/variants_all.fa \
  consensus_sracon_medaka_medaka.fa \
  -t $THREADS --cs |\
  $SAMTOOLS view -F 2308 - |\
  cut -f1-9,12,21 \
  > validation/consensus_sracon_medaka_medaka_variants.sam

$MINIMAP2 \
  -ax map-ont \
  $REF_VENDOR \
  consensus_sracon_medaka_medaka.fa \
  -t $THREADS --cs |\
  $SAMTOOLS view -F 2308 - |\
  cut -f1-9,12,21 \
  > validation/consensus_sracon_medaka_medaka_vendor.sam

### Copy refs
cp $REF validation/
cp $REF_VENDOR validation/

### Detect chimeras
$USEARCH -uchime2_ref consensus_sracon_medaka_medaka.fa \
  -uchimeout validation/consensus_sracon_medaka_medaka_chimera.txt \
  -db $REF \
  -strand plus \
  -mode sensitive

### Read stats
fastq_stats(){
  awk -v sample="$2" '
    NR%4==2{
      rc++
      bp+=length
    } END {
      print sample","rc","bp","bp/rc
    }
  ' $1
}

echo "data_type,read_count,bp_total,bp_average" > validation/data_stats.txt
fastq_stats ./reads.fq raw >> validation/data_stats.txt
fastq_stats ./umi_binning/trim/reads_tf.fq trim >> validation/data_stats.txt
