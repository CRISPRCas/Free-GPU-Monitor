#!/bin/bash

queue_file="training_queue.txt"
RED='\033[0;31m'
GREEN='\033[0;32m'
GRAY='\033[1;30m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

function print_queue {
  while read -r task; do
    IFS=',' read -r -a task_info <<< "$task"
    priority=${task_info[0]}
    id=${task_info[1]}
    script_path=${task_info[2]}
    num_gpus=${task_info[3]}
    pid=${task_info[4]}

    if [ "$pid" == "-1" ]; then
      status="${WHITE}Idle${NC}"
    elif [ "$pid" == "-2" ]; then
      status="${GRAY}Completed${NC}"
    elif [ "$pid" == "-3" ]; then
      status="${RED}Failed${NC}"
    else
      status="${GREEN}Running${NC}"
    fi

    echo -e "Priority: $priority, Task ID: $id, Script Path: $script_path, GPUs Required: $num_gpus, PID: $pid, Status: $status"
  done < <(sort -t',' -k1rn $queue_file) # Print in descending order of priority
}

while true; do
  echo "Please choose an action:"
  echo "1. Add a task"
  echo "2. Remove a task"
  echo "3. Kill a task"
  echo "4. Change task priority"
  echo "5. Print the queue"
  echo "6. Renew a task"
  echo "7. Exit"

  read action

  case $action in
    1)
      echo "Enter the task script path:"
      read script_path
      echo "Enter the number of GPUs required:"
      read num_gpus
      id=$(uuidgen)
      max_priority=$(cut -d',' -f1 $queue_file | sort -rn | head -n1)
      new_priority=$((max_priority + 1))
      echo "$new_priority,$id,$script_path,$num_gpus,-1" >> $queue_file
      ;;
    2)
      echo "Enter the task ID to remove:"
      read task_id
      sed -i "/,$task_id,/d" $queue_file
      ;;
    3)
      echo "Enter the task ID to kill:"
      read task_id
      pid=$(awk -F',' "/,$task_id,/ { print \$5 }" $queue_file)
      if [ "$pid" != "-1" ] && [ "$pid" != "-2" ] && [ "$pid" != "-3" ]; then
        kill $pid
        sed -i "/,${task_id},/ s/[^,]*$/-3/" $queue_file
      fi
      ;;
    4)
      echo "Enter the task ID to change priority:"
      read task_id
      echo "Enter the new priority:"
      read new_priority
      sed -i "/,${task_id},/ s/^[^,]*,/${new_priority},/" $queue_file
      ;;
    5)
      print_queue
      ;;
    6)
      echo "Enter the task ID to renew:"
      read task_id
      while IFS=',' read -r priority id script_path num_gpus pid; do
        if [ "$id" == "$task_id" ]; then
          echo "$priority,$id,$script_path,$num_gpus,-1" >> $queue_file.tmp
        else
          echo "$priority,$id,$script_path,$num_gpus,$pid" >> $queue_file.tmp
        fi
      done < $queue_file
      mv $queue_file.tmp $queue_file
      ;;
    7)
      exit 0
      ;;
    *)
      echo "Invalid action. Please enter a number from 1 to 7."
      ;;
  esac
done
