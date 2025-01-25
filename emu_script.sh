#!/bin/bash
set -e  # Exit on error

# Step 1: Function to concatenate fastq.gz files
concatenate_files() {
    local input_dir=$1
    local output_dir=$2
    mkdir -p "$output_dir"
    
    # Extract the base directory pattern from the subdirectories
    base_number=$(ls -d "$input_dir"/*_* | head -n1 | xargs basename | cut -d'_' -f1)
    echo "Base number identified: $base_number"
    
    start_time=$(date +%s)
    for i in "$input_dir"/"${base_number}"_*/; do
        if [ -d "$i" ]; then
            sample_id=$(basename "$i" | awk -F'_' '{print $NF}')
            cat "$i"/*.fastq.gz > "$output_dir/concatenated_${sample_id}.fastq.gz"
            echo "Processed directory: $i"
        fi
    done
    end_time=$(date +%s)
    echo "Concatenate files took $((end_time - start_time)) seconds."
}


# Step 2: Function to filter files with seqkit
module load seqkit/seqkit-0.12.0
filter_files() {
    local input_dir=$1
    local output_dir=$2

    mkdir -p "$output_dir"

    start_time=$(date +%s)
    for file in "$input_dir"/*.fastq.gz; do
        if [ -f "$file" ]; then
            sample_id=$(basename "$file" .fastq.gz | tr -dc '0-9')
            output_file="$output_dir/${sample_id}.fastq"
            
            # Check if output file already exists
            if [ -f "$output_file" ]; then
                echo "Skipping $file - output already exists: $output_file"
                continue
            fi
            seqkit seq -g -m 1200 -M 1800 -Q 10 "$file" > "$output_dir/${sample_id}.fastq"
            echo "Processed file: $file"
        fi
    done
    end_time=$(date +%s)
    echo "Filter files took $((end_time - start_time)) seconds."
# Unload the seqkit module
    module purge
}

# Step 3: Function to run NanoComp
run_nanocomp() {
    local input_dir=$1
    local output_dir=$2
    
    # Input validation
    if [ ! -d "$input_dir" ]; then
        echo "ERROR: Input directory '$input_dir' does not exist"
        return 1
    fi
    
    mkdir -p "$output_dir"
    
    # Ensure conda is available
    if [ ! -f "/opt/miniconda/miniconda3/etc/profile.d/conda.sh" ]; then
        echo "ERROR: Conda installation not found"
        return 1
    fi
    
    source /opt/miniconda/miniconda3/etc/profile.d/conda.sh
    
    # Check if conda environment exists
    if ! conda env list | grep -q "nanocomp_env"; then
        echo "ERROR: conda environment 'nanocomp_env' not found"
        return 1
    fi
    
    conda activate nanocomp_env
    
    start_time=$(date +%s)
    
    # Initialize arrays for files and names
    declare -a fastq_files
    declare -a names
    
    # Debug counter for file processing
    local file_count=0
    
    # Build arrays of files and names
    while IFS= read -r -d '' file; do
        if [ -f "$file" ] && [[ "$file" == *.fastq ]]; then
            fastq_files+=("$file")
            # Extract just the filename without path and extension
            basename=$(basename "$file" .fastq)
            names+=("$basename")
            ((file_count++))
            echo "DEBUG: Added file $file_count: $file"
            echo "DEBUG: Added name $file_count: $basename"
        fi
    done < <(find "$input_dir" -type f -name "*.fastq" -print0)
    
    # Validation checks
    if [ ${#fastq_files[@]} -eq 0 ]; then
        echo "ERROR: No .fastq files found in $input_dir"
        conda deactivate
        return 1
    fi
    
    if [ ${#fastq_files[@]} -ne ${#names[@]} ]; then
        echo "ERROR: Mismatch between number of files and names"
        conda deactivate
        return 1
    fi
    
    # Debug output
    echo "DEBUG: Found ${#fastq_files[@]} fastq files"
    echo "DEBUG: Files to process:"
    printf '%s\n' "${fastq_files[@]}"
    echo "DEBUG: Names to use:"
    printf '%s\n' "${names[@]}"
    
    # Construct NanoComp command
    local nanocomp_cmd="NanoComp --fastq"
    
    # Add each file to the command
    for file in "${fastq_files[@]}"; do
        nanocomp_cmd+=" \"$file\""
    done
    
    # Add names parameter
    nanocomp_cmd+=" --names"
    for name in "${names[@]}"; do
        nanocomp_cmd+=" \"$name\""
    done
    
    nanocomp_cmd+=" -o \"$output_dir\""
    
    # Debug: print full command
    echo "DEBUG: Executing command:"
    echo "$nanocomp_cmd"
    
    # Execute the command
    eval "$nanocomp_cmd"
    
    local nanocomp_exit=$?
    
    if [ $nanocomp_exit -ne 0 ]; then
        echo "ERROR: NanoComp failed with exit code $nanocomp_exit"
        conda deactivate
        return 1
    fi
    
    end_time=$(date +%s)
    echo "INFO: NanoComp completed successfully in $((end_time - start_time)) seconds"
    echo "INFO: Output written to $output_dir"
    
    conda deactivate
    return 0
}

# Step 4: Function to run emu abundance
run_emu_abundance() {
    local input_dir=$1
    local output_dir=$2
    local email=$3

    mkdir -p "$output_dir"

    # SLURM job configuration
    cat <<EOF > "$output_dir/emu_abundance.slurm"
#!/bin/bash
#SBATCH --job-name=emu_abundance
#SBATCH --error=emu_abundance.%j.err
#SBATCH --ntasks=1            # One task
#SBATCH --cpus-per-task=8     # 8 threads
#SBATCH --mem=16G             # 16 GB of memory
#SBATCH --w node02      # Specifically request node 2
#SBATCH --mail-user=$email
#SBATCH --mail-type=END,FAIL
#SBATCH --chdir=$output_dir  # Change to the output directory


# Activate the conda environment
source /opt/miniconda/miniconda3/etc/profile.d/conda.sh
conda activate /home/ang425/miniconda3/envs/emu_env

start_time=\$(date +%s)

# Run emu abundance for each file in the input directory
for file in "$input_dir"/*.fastq; do
    if [ -f "\$file" ]; then
        sample_id=\$(basename "\$file" .fastq)
        emu abundance "\$file" --keep-counts --keep-read-assignments --threads 8 \\
            --db ~/emu_prebuilt_db/ --output-unclassified \\
            --output-dir "$output_dir" \\
            --output-basename "\$sample_id"
        echo "Processed file: \$file"
    fi
done

end_time=\$(date +%s)
echo "Run emu abundance took \$((end_time - start_time)) seconds."

# Deactivate the conda environment
conda deactivate
EOF

    # Submit the SLURM job
    if ! sbatch "$output_dir/emu_abundance.slurm"; then
        echo "Error submitting SLURM job"
        exit 1
    fi
}

# Main script
main() {
    local wd="$1"
    local concat_dir="$wd/concat_fastqpass"
    local filtered_dir="$wd/seqfiltered"  # Change the filtered directory here    
    local nanocomp_output_dir="$wd/nanocomp_output"
    local emu_input_dir="$filtered_dir"
    local emu_output_dir="$wd/emu_results"    # EMU outpusqueuet directory
    local email="$2"
    
    concatenate_files "$wd" "$concat_dir"
    filter_files "$concat_dir" "$filtered_dir"
    run_nanocomp "$filtered_dir" "$nanocomp_output_dir"
    run_emu_abundance "$emu_input_dir" "$emu_output_dir" "$email"
}

# Check if the correct number of arguments is provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <input_directory> <email>"
    exit 1
fi

main "$@"
# End of script
#emu combine-outputs ~/5780_Nanopore/fastq_pass/emu_results tax_id --counts
