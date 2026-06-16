#!/bin/bash
#SBATCH --time=24:00:00
#SBATCH --tmp=200G
#SBATCH -p all
#SBATCH --nodes=1 
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=20G
#SBATCH --propagate=NONE


# Script preambles:
source /cbica/projects/pennlinc_rbc/miniforge3/bin/activate base

echo I\'m in $PWD using `which python`

# Fail whenever something is fishy, use -x to get verbose logfiles:
set -e -u -x

dssource="$1"	# i.e., `input_ria`
pushgitremote="$2"	# i.e., `output_ria`
SUBJECT_CSV="$3"

subject_row=$(head -n $((${SLURM_ARRAY_TASK_ID} + 1)) ${SUBJECT_CSV} | tail -n 1)
subid=$(echo "$subject_row" | sed -n 's/^.*\(sub-[A-Za-z0-9]*\).*$/\1/p')
sesid=$(echo "$subject_row" | sed -n 's/^.*\(ses-[A-Za-z0-9]*\).*$/\1/p')

# Change path to an ephemeral (temporary) job compute workspace:
# The path is specified according to 'job_compute_space' in container's configuration YAML file.
cd ${TMP}

# Branch name (also used as temporary directory):
BRANCH="job-${SLURM_ARRAY_JOB_ID}-${subid}-${sesid}"
mkdir ${BRANCH}
cd ${BRANCH}

# Clone the data from input RIA:
datalad clone "${dssource}" ds
cd ds
# Register output RIA as remote for result deposition:
git remote add outputstore "${pushgitremote}"

# Create a new branch for this job's results:
git checkout -b "${BRANCH}"

# Pull down the input subject (or dataset) but don't retrieve data contents:
datalad get -n "inputs/data/BIDS/${subid}"
(cd inputs/data/BIDS && rm -rf `find . -type d -name 'sub*' | grep -v $subid`)

# datalad run:
datalad run \
	-i code/fmriprep-25-0-0_zip.sh \
	-i inputs/data/BIDS/${subid}/${sesid} \
	-i inputs/data/BIDS/*json \
	-i containers/.datalad/environments/fmriprep-25-0-0/image \
	--expand inputs \
	--explicit \
	-o ${subid}_${sesid}_fmriprep_anat-25-0-0.zip \
	-m "fmriprep-25-0-0 ${subid} ${sesid}" \
	"bash ./code/fmriprep-25-0-0_zip.sh ${subid} ${sesid}"

# Push result file content to output RIA storage:
datalad push --to output-storage
# Push the branch with provenance records:
flock $DSLOCKFILE git push outputstore

echo 'Delete temporary directory:'
echo ${BRANCH}
datalad drop -d inputs/data/BIDS -r --reckless availability --reckless modification
datalad drop -r . --reckless availability --reckless modification
git annex dead here
cd ../..
rm -rf $BRANCH

echo SUCCESS
