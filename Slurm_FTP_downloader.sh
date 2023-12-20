#!/bin/bash
date;hostname
echo "The directory in which Patric_genome_downloader was run is: "
echo $(pwd)

# This function will change the working 
# directory to the directory in which 
# Patric_genome_downloader project exists
# to be sure utilities are loaded correctly!
aanpasbaar_runing() {
  local initial_working_directory=$1
  local Patric_genome_downloader_directory=$2
  if [ "$initial_working_directory" != "$Patric_genome_downloader_directory" ]; then
      # Change the working directory to the target directory
      cd "$Patric_genome_downloader_directory" || { echo -e "\e[31mError occurred changing" \
      "the working directory to directory of Patric_genome_downloader, program aborted!\e[0m"; exit 2; }
  fi
}
# This path variable is created to be able to run Patric_genome_downloader
# from any directorys in system using absolute path
Patric_genome_downloader_DIR="$(dirname "$(readlink -f "$0")")"

# Check if the current directory is not equal to the target directory
# This will make the software easily executable from any directories on the system


# if [ "$PWD" != "$Patric_genome_downloader_DIR" ]; then
#     # Change the working directory to the target directory
#     cd "$Patric_genome_downloader_DIR" || { echo -e "\e[31mError occurred changing the working directory to directory of Patric_genome_downloader, program aborted!\e[0m"; exit 2; }
# fi   # Followin function | | |
#                          V V V
aanpasbaar_runing $PWD $Patric_genome_downloader_DIR

current_directory=$(pwd)
echo "the current working directory is :$current_directory"
#Processing args

#loading utilities and usage functions 
source $current_directory/utils/utils.sh

# Processing arguments


#!/bin/bash

# Default values for optional arguments
rwX_group_access=0
memory=10
cpus=2
time_limit=20
logs=0


# Parse command-line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -rwXg)
            shift
            rwX_group_access="$1"
            ;;
        -m|--memory)
            shift
            memory="$1"
            ;;
        -c|--cpus)
            shift
            cpus="$1"
            ;;
        -t|--time_limit)
            shift
            time_limit="$1"
            ;;
        -l|--logs)
            shift
            logs="$1"
            ;;
        -f|--File_type)
            shift
            case "$1" in
                fna|faa|features.tab|ffn|frn|gff|pathway.tab|spgene.tab|subsystem.tab)
                    File_type="$1"
                    ;;
                *)
                    echo -e "\e[31mError: Invalid FILE_TYPE (-f ).\e[0m"
                    usage
                    ;;
            esac
            ;;
        -o|--genomes_saving_directory)
            shift
            genome_saving_directory="$1"
            ;;
        -i|--Address_to_genome_id_text_file)
            shift
            Address_to_genome_id_text_file="$1"
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "\e[31mError: Unknown option $1\e[0m"
            usage
            ;;
    esac
    shift
done

# Check for missing required arguments
if [ -z "$File_type" ] || [ -z "$genome_saving_directory" ] || [ -z "$Address_to_genome_id_text_file" ]; then
    echo -e "\e[31mError: Required argument is missing!\e[0m"
    usage
fi


Needed_memory="$memory"gb
number_of_accessible_CPUs=${cpus}
Process_time=$time_limit:00:00

# Slrum specifications
Main_job_action_name="DV_BRC_genome_downloader"
log_files_address=${current_directory}"/temp/logs_"${Main_job_action_name}
slurm_script_address=${current_directory}/temp/${Main_job_action_name}.sh
Array_job_list=1-${number_of_accessible_CPUs} 


# +-------------------------- main code ---------------------------+
# loading the utilities
source ${Patric_genome_downloader_DIR}/utils/utils.sh 

# Creating temporaty directory
create_directory ${current_directory}"/temp"

# Creating log directory for the debug 
if [ $logs -eq 1 ]; then
    create_directory ${log_files_address}
    grant_permissions ${log_files_address}
fi

# # Checking group flag
if [ "$rwX_group_access" -eq 1 ]; then

    grant_permissions ${current_directory}

fi

# #This part creates .sh file optimized based 
# # on the system of the genome id files used 

# reading the textfile containing the genome IDs
text_file_finder_and_sanity_checker_corrector $Address_to_genome_id_text_file

Number_of_genomes=$(awk 'END{print NR}' "$Address_to_genome_id_text_file")
echo "Number of genomes to be downloaded:" $Number_of_genomes

create_directory ${genome_saving_directory}

if [ "$rwX_group_access" -eq 1 ]; then

    grant_permissions ${genome_saving_directory}

fi

cat << EOF > ${slurm_script_address}
#!/bin/bash
#SBATCH --job-name=${Main_job_action_name}
#SBATCH --mail-type=ALL            # Mail events (NONE, BEGIN, END, FAIL, ALL)
#SBATCH --mail-user=${Mail_user}   # Where to send mail
#SBATCH --ntasks=1                       # Run a single task
#SBATCH --mem=${Needed_memory}                        # Job Memory
#SBATCH --time=${Process_time}                 # Time limit hrs:min:sec
#SBATCH --array=${Array_job_list}                  # Array range
#SBATCH --output=${log_files_address}/"$Main_job_action_name"_%A_%a.log


RUN=\${SLURM_ARRAY_TASK_ID:-1}

echo "RUN #\${RUN}"

INPUT_LIST=${Address_to_genome_id_text_file}

Number_of_genomes=\$(wc -l < "\$INPUT_LIST")

# Calculate the number of lines each CPU should process (ceiling)
lines_per_cpu=$(awk -v total="$Number_of_genomes" -v cpus="$number_of_accessible_CPUs" 'BEGIN { print int((total + cpus - 1) / cpus) }')
echo \$lines_per_cpu is allocated to each CPU



# Calculate the start and end lines for the current job
start_line=\$(((SLURM_ARRAY_TASK_ID - 1) * lines_per_cpu + 1))
end_line=\$((start_line + lines_per_cpu - 1))

if [ "\$end_line" -ge "\$total_lines" ]; then
    end_line="\$((\$Number_of_genomes - 1))"
fi
echo "starting line =" \$start_line
echo "Ending line   =" \$end_line

# Process lines in the specified interval
for ((line_num = \$start_line; line_num <= \$end_line; line_num++)); do

    INPUT_FILE=\$(sed -n "\${line_num}p" "\$INPUT_LIST")

    echo "Downloading genome ID \${INPUT_FILE}, .$File_type file from DV-BRC database"
    genome_saving_address=${genome_saving_directory}/\${INPUT_FILE}.$File_type


    # Checking the genome is already downloaded
    if [ ! -f "\$genome_saving_address" ]; then

        echo -e "\e[32m\${INPUT_FILE}.$File_type is being downloaded!\e[0m"

        if wget -qN -P "${genome_saving_directory}" "ftp://ftp.bvbrc.org/genomes/\${INPUT_FILE}/\${INPUT_FILE}.$File_type"; then
        # Command was successful
            echo -e "\e[32m\${INPUT_FILE}.$File_type successfuly downloaded!!!!!!!\e[0m"  # Green text
        else
            # Command failed
            echo -e "\e[31m\${INPUT_FILE}.$File_type failed to be downloaded!!!!!!\e[0m"  # Red text
        fi

    else # starting to download the genome
        echo "\${INPUT_FILE}.$File_type is already downloaded exists in the dataset directory!"
    fi  

done

echo The batch of .$File_type files in $Address_to_genome_id_text_file text file are downloaded!
echo Finished!!!

EOF


if [ "$rwX_group_access" -eq 1 ]; then

    grant_permissions ${slurm_script_address}

fi

sbatch ${slurm_script_address}

echo ${Main_job_action_name} is submitted!

