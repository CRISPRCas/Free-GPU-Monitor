#!/bin/bash

queue_file="training_queue.txt"
log_file="log/monitor_and_train.log"

if [ ! -d "./log" ]; then
  mkdir ./log
fi

function run_task {
  task_line=$1
  IFS=',' read -r -a task_info <<< "$task_line"
  priority=${task_info[0]}
  id=${task_info[1]}
  script_path=${task_info[2]}
  num_gpus=${task_info[3]}
  pid=${task_info[4]}

  if [ "$pid" == "-1" ]; then
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    available_gpus=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | awk '$1 <= 300 { print NR-1 }')
    gpu_ids=$(echo $available_gpus | tr ' ' '\n' | head -n $num_gpus | tr '\n' ',')
    gpu_ids=${gpu_ids%?} # remove trailing comma
    echo "$timestamp: Starting task $id with GPU $gpu_ids" >> $log_file
    {
      export CUDA_VISIBLE_DEVICES=$gpu_ids
      nohup /bin/bash $script_path &
    } >> "log/task_${id}_log.txt" 2>&1 &
    new_pid=$(pgrep -f $script_path | xargs)
    {
      wait $new_pid && echo "Task completed successfully"
    } >> "log/task_${id}_log.txt" 2>&1 &  # Add this task to the background as well
    sed -i "s|^$priority,$id,.*$|$priority,$id,$script_path,$num_gpus,$new_pid|" $queue_file # Update PID in queue file
  fi
}


function update_task_status {
  task_line=$1
  IFS=',' read -r -a task_info <<< "$task_line"
  priority=${task_info[0]}
  id=${task_info[1]}
  script_path=${task_info[2]}
  num_gpus=${task_info[3]}
  pid=${task_info[4]}

  if [ -n "$pid" ] && [ "$pid" -eq "$pid" ] 2>/dev/null; then
    if [ "$pid" != "-1" ] && [ "$pid" != "-2" ] && [ "$pid" != "-3" ]; then
      if ! ps -p $pid > /dev/null; then
        # Check the last line of the task's log file to determine success or failure
        if tail -n 2 "log/task_${id}_log.txt" | grep -q "Task completed successfully"; then
          new_pid="-2"  # Successful completion
          timestamp=$(date '+%Y-%m-%d %H:%M:%S')
          echo "$timestamp: Task $id completed successfully" >> $log_file
        else
          new_pid="-3"  # Task failure
          timestamp=$(date '+%Y-%m-%d %H:%M:%S')
          echo "$timestamp: Task $id failed" >> $log_file
        fi
        sed -i "s|^$priority,$id,.*$|$priority,$id,$script_path,$num_gpus,$new_pid|" $queue_file # Update PID in queue file
      fi
    fi
  fi
}


while true; do
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  available_gpus=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | awk -F ',' '{ if ($1<=300) print $1 }' | wc -l)
  echo "$timestamp: Checking GPU status, Aviable GPUs: $available_gpus" >> $log_file

  echo "$timestamp: Checking GPU status, Aviable GPUs: $available_gpus"

  # Process tasks in descending order of priority
  if [ ! -f "$queue_file" ] || [ ! -s "$queue_file" ]; then
    echo "$queue_file does not exist or is empty. Skipping..."
  else
    sort -t',' -k1rn $queue_file | while read -r task; do
      num_gpus_required=$(echo $task | cut -d',' -f4)
      pid=$(echo $task | cut -d',' -f5)

      update_task_status $task
      
      # Only run the task if its PID is -1 (idle)
      if [ "$pid" == "-1" ] && [ "$available_gpus" -ge "$num_gpus_required" ]; then
        echo "Start running task $task"
        run_task $task
        available_gpus=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | awk -F ',' '{ if ($1<=300) print $1 }' | wc -l)
      fi
    done
  fi

  sleep 30
done
