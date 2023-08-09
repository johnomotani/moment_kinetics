#!/bin/bash

set -e

# job settings for the run
##########################

# Get setup for Julia
source julia.env

JOBINFO=($(util/get-job-info.jl))
MACHINE=${JOBINFO[0]}
ACCOUNT=${JOBINFO[1]}
RUNTIME=${JOBINFO[2]}
NODES=${JOBINFO[3]}
POSTPROCTIME=${JOBINFO[4]}
POSTPROCMEMORY=${JOBINFO[5]}
PARTITION=${JOBINFO[6]}
QOS=${JOBINFO[7]}

# Parse command line options
# [See e.g. https://www.stackchief.com/tutorials/Bash%20Tutorial%3A%20getopts
# for examples of how to use Bash's getopts]
POSTPROC=0
RESTARTFROM=""
FOLLOWFROM=""
while getopts "hr:t:n:u:m:p:q:af:" opt; do
  case $opt in
    h)
      echo "Submit jobs for a simulation (using INPUT_FILE for input) and post-processing to the queue
Usage: submit-run.sh [option] INPUT_FILE
-h             Print help and exit
-r FILE        The output file to restart from (defaults to latest output in the run directory)
-t TIME        The run time, e.g. 24:00:00
-n NODES       The number of nodes to use for the simulation
-u TIME        The run time for the post-processing, e.g. 1:00:00
-m MEM         The requested memory for post-processing
-p PARTITION   The 'partition' (passed to 'sbatch --partition')
-q QOS         The 'quality of service' (passed to 'sbatch --qos')
-a             Do not submit post-processing job after the run
-f JOBID       Make this job start after JOBID finishes successfully"
      exit 1
      ;;
    r)
      RESTARTFROM=$OPTARG
      ;;
    t)
      RUNTIME=$OPTARG
      ;;
    n)
      NODES=$OPTARG
      ;;
    u)
      POSTPROCTIME=$OPTARG
      ;;
    m)
      POSTPROCMEM=$OPTARG
      ;;
    p)
      PARTITION=$OPTARG
      ;;
    q)
      QOS=$OPTARG
      ;;
    a)
      POSTPROC=1
      ;;
    f)
      FOLLOWFROM="-d afterok:$OPTARG"
      ;;
  esac
done

# Get the positional argument as INPUTFILE
# [See https://stackoverflow.com/a/13400237]
INPUTFILE=${@:$OPTIND:1}
if [ -z "$INPUTFILE" ]; then
  echo "No input file passed - must pass an input file name as a positional argument"
  exit 1
fi

RUNNAME=$(util/get-run-name.jl $INPUTFILE)

RUNDIR=runs/$RUNNAME/
mkdir -p $RUNDIR

# Get default file to restart from, which is the latest run in $RUNDIR
if [[ -z $RESTARTFROM ]]; then
  # "shopt -s extglob" is needed to let us use the ?() syntax within a script
  # (it doesn't seem to be needed in an interactive shell!). See
  # https://www.linuxjournal.com/content/pattern-matching-bash
  shopt -s extglob
  RESTARTFROM=$(ls $RUNDIR/$RUNNAME.dfns*.?(h5|cdf) | head -n 1)
fi

if [[ $POSTPROC -eq 0 ]]; then
  echo "Submitting $INPUTFILE for restart from $RESTARTFROM and post-processing..."
else
  echo "Submitting $INPUTFILE for restart from $RESTARTFROM..."
fi

# Create a submission script for the run
RESTARTJOBSCRIPT=${RUNDIR}$RUNNAME-restart.job
sed -e "s|NODES|$NODES|" -e "s|RUNTIME|$RUNTIME|" -e "s|ACCOUNT|$ACCOUNT|" -e "s|PARTITION|$PARTITION|" -e "s|QOS|$QOS|" -e "s|RUNDIR|$RUNDIR|" -e "s|INPUTFILE|$INPUTFILE|" -e "s|RESTARTFROM|$RESTARTFROM|" machines/$MACHINE/jobscript-restart.template > $RESTARTJOBSCRIPT

JOBID=$(sbatch $FOLLOWFROM --parsable $RESTARTJOBSCRIPT)
echo "Restart: $JOBID"
echo "In the queue" > ${RUNDIR}slurm-$JOBID.out

if [[ $POSTPROC -eq 0 ]]; then
  # Create a submission script for post-processing
  POSTPROCJOBSCRIPT=${RUNDIR}$RUNNAME-post.job
  sed -e "s|POSTPROCMEMORY|$POSTPROCMEMORY|" -e "s|POSTPROCTIME|$POSTPROCTIME|" -e "s|ACCOUNT|$ACCOUNT|" -e "s|RUNDIR|$RUNDIR|" machines/$MACHINE/jobscript-postprocess.template > $POSTPROCJOBSCRIPT

  POSTID=$(sbatch -d afterany:$JOBID --parsable $POSTPROCJOBSCRIPT)
  echo "Postprocess: $POSTID"
  echo "In the queue" > ${RUNDIR}slurm-post-$POSTID.out
fi

echo "Done"