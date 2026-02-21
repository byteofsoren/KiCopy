#!/bin/bash

# 4. Symlink it (without the .py so you just type `myapp`)
# ln -s /home/user/repo/app/src/myapp.py ~/.local/bin/myapp

# This script updates the REPO path in a target file (assumed to be 'original_script.sh' here).
# Replace 'original_script.sh' with the actual file path if different.
TARGET_FILE="./src/test.sh"
NEW_PATH=""

set_path_to_repo() {
  # Check if new path was provided
  # Expand ~ to $HOME if the path starts with it
  local path=$1
  echo "path=$path"

  if [[ $path == ~* ]]; then
    path="${path/#\~/$HOME}"
  fi

  # Resolve to full absolute path (assuming the directory exists; requires 'realpath' which is common on most systems)
  echo "path=$path"
  NEW_PATH=$(realpath "$path")
  echo "NEW_PATH=$NEW_PATH"

  if [ -z "$NEW_PATH" ]; then
    echo "Error: Missing required argument -r or --repo with the new path."
    echo "Usage: $0 [-r|--repo] <new_path>"
    exit 1
  fi

  # Check if the target file exists
  if [ ! -f "$TARGET_FILE" ]; then
    echo "Error: Target file '$TARGET_FILE' does not exist."
    exit 1
  fi

  # Use sed to replace the REPO line in place
  sed -i "s|^REPO=.*|REPO=\"\$HOME${NEW_PATH/$HOME/}\"|" "$TARGET_FILE"

  echo "Updated REPO path in '$TARGET_FILE' to '$NEW_PATH'."

  echo ""
  echo "Show results"
  cat ./src/test.sh

}

set_path_to_kicopy() {
  echo "start"
  local path
  path="$(pwd)"
  echo "$path"
  # ln -s /home/user/repo/app/src/myapp.py ~/.local/bin/myapp
  if [[ ! -e "$path/src/kicopy.sh" || ! -f "$path/src/kicopy.sh" ]]; then
    echo "KiCopy ERROR"
    exit
  fi
  if [[ -e "$HOME/.local/bin/kicopy" ]]; then
    echo "KiCopy already installed or there is a conflict"
    exit
  fi
  ln -s "$path/src/kicopy.sh" "$HOME/.local/bin/kicopy"
}
remove_path_to_kicopy() {
  echo "start"
  local path
  path="$(pwd)"
  echo "$path"
  # ln -s /home/user/repo/app/src/myapp.py ~/.local/bin/myapp
  if [[ ! -e "$HOME/.local/bin/kicopy" || ! -L "$HOME/.local/bin/kicopy" ]]; then
    echo "Target did not exists"
  fi
  echo "Removing the symlink from:"
  echo " $HOME/.local/bin/kicopy"
  unlink "$HOME/.local/bin/kicopy"

}

show_help() {
  echo "KiCopy show help!"
  echo ""
  echo "KiCopy. Installs the KiCopy by symlink over to ~/.local/bin/kicopy "
  echo "By using the -r or --repo [target dir] that allows the to change the repo"
  echo ""
  echo "Synopsis"
  echo "-i or --install sets the path from src/kicopy.sh to .local/bin/kicopy"
  echo "-r or --repo sets the repo target for KiCopy"
  echo "--remove removes the symlink in .local/bin/kicopy"
  echo ""
  echo "Example:"
  echo " install.sh -i --repo ~/repos/component_repo"

}

OPTIONS=$(getopt -o i,r:,h --long install,repo:,remove,help -- "$@")
eval set -- "$OPTIONS"

# Parse command-line arguments
while true; do
  case $1 in
  -i)
    set_path_to_kicopy
    shift
    ;;
  -r)
    set_path_to_repo "$2"
    shift
    ;;
  -h)
    show_help
    shift
    ;;
  --install)
    set_path_to_kicopy
    shift
    ;;
  --remove)
    remove_path_to_kicopy
    shift
    ;;
  --repo)
    set_path_to_repo "$2"
    shift
    ;;
  --help)
    show_help
    shift
    ;;

  --)
    shift
    break
    ;;
  *)
    echo "Unknown option: $1"
    echo "Usage: $0 [-r|--repo] <new_path>"
    exit 1
    ;;
  esac
done
