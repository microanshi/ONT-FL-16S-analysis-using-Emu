# ONT-FL-16S-analysis-using-Emu
This pipeline contains all the steps required to generate taxonomic abundance data from ONT full-length 16S rRNA reads

# EMU Pipeline

This repository contains a Bash script for processing sequencing data using the `emu` tool.

## Requirements
- Bash
- SeqKit
- NanoComp
- Emu
- SLURM (for job scheduling)

## Dependencies

Install SeqKit: conda install -c bioconda seqkit
Install NanoComp: conda install -c bioconda nanocomp
Install Emu: Follow the instructions at [Emu GitHub](https://github.com/treangenlab/emu)

## Usage
#Make the script executable 
chmod +x emu_script.sh

#Run the script
./emu_script.sh /path/to/input_directory your_email@example.com
