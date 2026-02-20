#!/bin/bash
# ================================================
# KiCad ZIP → organized repo (one-liner speed)
# Run this from the folder that contains all your *.zip files
# ================================================

REPO="$HOME/repos/electricdesign_kilib"

# ================================================
# Global do not change
# ================================================
TEMP="/tmp/kicad_extract_$$"
FOOTPRINTS="$REPO/footprints"
SYMBOLS="$REPO/symbols"
VISUALFILES="$REPO/3d"
DESIGNBLOCK="$REPO/design_blocks"

TARGET=""
CHECKTARGET=False
SHOWHELP=False
COUNTER=0

# Status table reports after the process is done
FILE_STATUS_TABLE=""

# ================================================

# ================================================
# Error codes
# ================================================
readonly OK=0
readonly ERROR=1
# readonly FILENOTFOUND=2
# readonly FILEEXISTS=3
# readonly FILENOTCHANGED=6
readonly ALREADYDONE=4
# readonly NOTARGET=5
readonly IGNOREFILE=7
readonly OVERWRITEFILE=8
readonly RENAMEDFILE=9
readonly NOCONFLICTONFILE=0
# ================================================
# Colors
# ================================================
readonly NO_FORMAT="\033[0m"
readonly C_TURQUOISE="\033[38;5;45m"
readonly C_GREEN="\033[38;5;48m"
readonly C_RED="\033[38;5;203m"
readonly C_LIME="\033[38;5;10m"
# ================================================

OPTIONS=$(getopt -o t:c --long target:,check,help -- "$@")
eval set -- "$OPTIONS"

# ================================================
# Truncate filenames for showing in the table.
# Base setting max length 25.
# How to use:
# truncated=$(truncate_filename "$filename")
# ================================================
truncate_filename() {
  local filename="$1"
  local max_len=25
  local ellipsis="..." # Or use "xxxx" to match your example style
  local len_ellipsis=${#ellipsis}
  local len=${#filename}

  if ((len <= max_len)); then
    printf "%s" "$filename"
    return
  fi

  local ext="${filename##*.}"
  local dot_ext=".${ext}"
  local len_dot_ext=${#dot_ext}

  # Calculate prefix length (aim for balanced, but ensure room for ellipsis + extension)
  local prefix_len=$((max_len - len_ellipsis - len_dot_ext))
  if ((prefix_len < 1)); then
    prefix_len=1 # Minimum to avoid empty prefix
  fi

  local prefix="${filename:0:prefix_len}"

  printf "%s%s%s" "$prefix" "$ellipsis" "$dot_ext"
}

# ================================================
# File status functions to for files moved
# ================================================
show_status_table() {
  if [[ -z $FILE_STATUS_TABLE ]]; then
    printf "| %-5s | %-25s | %-25s | %-10s |\n" "Id" "Base" "Target" "Status"
    printf "|-%s-+-%s-+-%s-+-%s-|" "$(printf '%.5s' '-----')" "$(printf '%.25s' '-------------------------')" "$(printf '%.25s' '-------------------------')" "$(printf '%.10s' '-----------')"
    printf '%s\n' "${FILE_STATUS_TABLE[@]}"
  else
    echo "NO file status to show!"
  fi
}

# ================================================
# Add status row:
# $1 id counter
# $2 base target with out change
# $3 target changed name to
# $4 Actions taken on file.
#
#   Action taken:
#     $OK if there are no conflics.
#     $RENAMEDFILE if the there where conflicts and it was renamed.
#     $IGNOREFILE if the there where conflics but the user chouses to ignore the file.
#     $ERROR If the user wants to abbort the process.
#
# How to use:
#   add_status_row "2" "THVD151.mod" "TVD1512_b.mod" "Changed"
# ================================================
add_status_row() {
  local id="$1"
  local base="$2"
  local target="$3"
  local base_trunk=""
  local target_trunk=""
  local status=""
  local action="$4"
  if [[ "$action" == "$OK" ]]; then
    status="OK"
  elif [[ "$action" == "$RENAMEDFILE" ]]; then
    status="Renamed"
  elif [[ "$action" == "$IGNOREFILE" ]]; then
    status="Ignored"
  elif [[ "$action" == "$ERROR" ]]; then
    status="ERROR"
  fi
  base_trunk=$(truncate_filename "$base")
  target_trunk=$(truncate_filename "$target")

  FILE_STATUS_TABLE+=("$(printf "| %5d | %-25s | %-25s | %-10s |\n" "$id" "$base_trunk" "$target_trunk" "$status")")
}

# ================================================
# Check repo status
# ================================================
check_repo_status() {
  local isok=True
  local status="OK"
  printf "| %-15s | %-8s |\n" "Directory" "Status"
  if [[ ! -e "$REPO" ]]; then
    isok=False
    status="FAIL"
  else
    status="Exists"
  fi
  printf "| %-15s | %-8s |\n" "Repo" "$status"
  if [[ ! -e "$FOOTPRINTS" ]]; then
    isok=False
    status="FAIL"
  else
    status="Exists"
  fi
  printf "| %-15s | %-8s |\n" "Footprints" "$status"
  if [[ ! -e "$SYMBOLS" ]]; then
    isok=False
    status="FAIL"
  else
    status="Exists"
  fi
  printf "| %-15s | %-8s |\n" "Symbols" "$status"
  if [[ ! -e "$VISUALFILES" ]]; then
    echo "Repo/3d did not exist"
    isok=False
    status="FAIL"
  else
    status="Exists"
  fi
  printf "| %-15s | %-8s |\n" "3D dir" "$status"
  if [[ ! -e "$DESIGNBLOCK" ]]; then
    echo "Repo/design_blocks did not exist"
    isok=False
    status="FAIL"
  else
    status="Exists"
  fi
  printf "| %-15s | %-8s |\n" "Design Blocks" "$status"

  if [[ $isok == False ]]; then
    return $ERROR
  fi
  return $OK
}

# ================================================
# Target should only be assigned onec.
# ================================================
target_assign_once() {
  echo "Start target_type_check"
  if [[ -n $TARGET ]]; then
    echo "ALREADYDONE"
    return $ALREADYDONE
  fi
  TARGET="$1"
}

# ================================================
# target conflicts
# Inputs:
#   target_dir=$1     like: $REPO/footprint/
#   base_filename=$2  like TVD1512.mod
#
# Return:
#   Action taken:
#     $OK if there are no conflics.
#     $RENAMEDFILE if the there where conflicts and it was renamed.
#     $IGNOREFILE if the there where conflics but the user chouses to ignore the file.
#     $ERROR If the user wants to abbort the process.
#
#   Observe that the base_filename can be changed by this script
#   For example: If "TVD1512.mod" exists you are getting an option
#   to change the name to "TVD1512_b.mod" or owerwrite.
#   The return is what to do.
#
# How to use:
#   action=move_to_repo_cehck "$REPO/mydir" file_name
# ================================================
move_to_repo_cehck() {
  local target_dir=$1
  local -n base_filename=$2
  local returnval="$OK"
  local orginal_fliename="$base_filename"
  # Does the file exist?!
  if [[ -e "$target_dir/$base_filename" ]]; then
    while true; do
      # Yes the target haid an file allready!
      echo -e " ${C_RED}File Exists${NO_FORMAT}"
      printf "What should I do?\n"
      # printf "[I]gnore [r]ename [o]verwrite:"
      printf "Rename, ingnore or break R/i/b: "
      read -n 1 -r conflict_ans
      echo ""

      # Rename r
      if [[ $conflict_ans == "r" || $conflict_ans == "R" ]]; then
        local new_filename=""
        # Extract new extension
        if [[ "$base_filename" == *.* ]]; then
          old_ext="${base_filename##*.}"
        else
          old_ext=""
        fi

        # Rename loop
        while true; do
          read -r -p "Rename the file $base_filename to: " new_filename
          [[ -z "$new_filename" ]] && {
            echo "No name enterd"
            continue
          }
          # Extract new extension
          if [[ "$new_filename" == *.* ]]; then
            new_ext="${new_filename##*.}"
          else
            new_ext=""
          fi
          # Check match: exact ext, or both have no ext
          # Both file extensions must match so thta the newfile.txt is equal to oldfile.txt
          if [[ "$new_ext" == "$old_ext" ]]; then

            # Safety: Don't overwrite existing
            [[ -e "$target_dir/$new_filename" ]] && {
              echo "${C_RED}Error:$NO_FORMAT $C_GREEN'$base_filename'$NO_FORMAT already exists."
              continue
            }

            # Full new path (assume same dir; adjust if needed)
            base_filename="$new_filename"

          else
            if [[ -n "$old_ext" ]]; then
              echo "❌ Invalid: Must end with .$old_ext (got .$new_ext)"
            else
              echo "❌ Invalid: Original has no extension—don't add one."
            fi
          fi
        done

        returnval="$RENAMEDFILE"
        break
      # Overwrite
      elif [[ $conflict_ans == "i" || $conflict_ans == "I" ]]; then
        returnval="$IGNOREFILE"
        break
      else
        returnval="$ERROR"
        break
      fi
    done
  fi
  # Add the row to the output table
  add_status_row "$COUNTER" "$base_filename" "$orginal_fliename" "$returnval"
  # Return with the return val
  return "$returnval"
}

# ================================================
# Sort the target
# ================================================
sort_target() {

  # Footprints → footprint/ (whole .pretty libraries)
  echo "Start footprints:"
  while IFS= read -r -d '' file; do
    # process "$file"
    # fname is the name of the file excluding the path to the file
    local fname=""
    fname=$(basename "$file")

    # Move to repo check checks if there is going to be any conflicts moving the file.
    move_to_repo_cehck "$FOOTPRINTS" fname
    local acction=$?

    # If CHECKTARGET is false then move the files from source to target dir.
    if [[ $CHECKTARGET == false ]]; then
      echo "Move the files to $REPO"
      # echo "mv $file $FOOTPRINTS/$fname"
      mv "$file" "$FOOTPRINTS/$fname"
    fi
    ((COUNTER++))
  done < <(find "$TEMP" \( -type d -name "*.pretty" \) -print0)
  echo "Moved $COUNTER, files"

  # Any loose footprint files
  echo "Start footprints any loose:"
  while IFS= read -r -d '' file; do
    local fname=""
    fname=$(basename "$file")
    # Do the target_conflict here
    move_to_repo_cehck "$FOOTPRINTS" fname
    local acction=$?

    if [[ $CHECKTARGET == False ]]; then
      # echo "Move the files to $REPO"
      # echo "mv $file $FOOTPRINTS/$fname"
      mv "$file" "$FOOTPRINTS/$fname"
      if ((acction == NOCONFLICTONFILE || acction == OVERWRITEFILE)); then
        # Move the file to repo
        printf " OK"

      elif ((acction == IGNOREFILE)); then
        printf " IG"
      fi
    fi
    ((COUNTER++))
  done < <(find "$TEMP" \( -name "*.kicad_mod" -o -name "*.mod" \) -print0)

  # Symbols + docs → symbols/
  echo "Start symbols files"
  while IFS= read -r -d '' file; do
    local fname=""
    fname=$(basename "$file")
    # Do the target_conflict here
    move_to_repo_cehck "$SYMBOLS" fname
    local acction=$?
    # process "$file"

    # If check target is False then then move the files in to repo
    if [[ $CHECKTARGET == False ]]; then
      echo "Move the files"
      # echo "mv $file $SYMBOLS/$fname"
      mv "$file" "$FOOTPRINTS/$fname"
    fi
    ((COUNTER++))
  done < <(find "$TEMP" \( -name "*.kicad_sym" -o -name "*.lib" -o -name "*.dcm" \) -print0)

  # 3D files
  echo "Start 3d files"
  while IFS= read -r -d '' file; do
    local fname=""
    fname=$(basename "$file")
    # Do the target_conflict here
    move_to_repo_cehck "$VISUALFILES" fname
    local acction=$?
    # process "$file"

    # If check target is False then then move the files in to repo
    if [[ $CHECKTARGET == False ]]; then
      echo "Move the files"
      # echo "mv $file $VISUALFILES/$fname"
      mv "$file" "$FOOTPRINTS/$fname"
    fi
    ((COUNTER++))
  done < <(find "$TEMP" \( -iname "*.wrl" -o -iname "*.step" -o -iname "*.stp" -o -iname "*.idf" -o -iname "*.stl" -o -iname "*.ply" -o -iname "*.glb" -o -iname "*.brep" -o -iname "*.xao" \) -print0)

}

# ================================================
# Get options
# ================================================
while true; do
  case "$1" in
  -t)
    target_assign_once "$2"
    shift
    ;;
  -c) CHECKTARGET=True ;;
  --target)
    target_assign_once "$2"
    shift
    ;;
  --check)
    echo "Enable check"
    CHECKTARGET=True
    ;;
  --help)
    echo "Help start"
    SHOWHELP=True
    ;;
  --)
    shift
    break
    ;;
  *)
    echo "Invalid option"
    exit 1
    ;;
  esac
  shift
done

if [[ $SHOWHELP == True ]]; then
  echo -e "$C_TURQUOISE KiCopy $NO_FORMAT"
  echo -e "KiCopy helps with adding symbols and footprints to your repo."
  echo -e "Currently the repo is set to$C_TURQUOISE $REPO$NO_FORMAT"
  echo -e "KiCopy can target both induvidual zip files and directories of zipfiles"
  echo -e "The following switches is provided"
  echo -e " \$ kicopy [-t (target) -c] or [--target (target) --check --help]"
  echo ""
  echo -e "-t or --target (target) where the target is a zip file or a directory of zip files"
  echo -e "-c or -check By enabling this flag, the progam only show the files and do not move them."
  echo -e "--help shows this help"
  echo ""
  echo "Examples:"
  echo "Move the footprints from the a zip to repo"
  echo -e " $C_LIME\$ kicopy --target LIB_THVD151.zip$NO_FORMAT\n"
  echo -e "Do not move the content from \n\tthe zipfile only shows the content"
  echo -e " $C_LIME\$ kicopy --target LIB_THVD151.zip --check$NO_FORMAT\n"
  echo "The target is a directory that contains zipfiles"
  echo -e "Extract the zipfiles and then move the footprints and symbols in to your repo."
  echo -e " $C_LIME\$ kicopy --target ~/tmp/foootprints$NO_FORMAT"
  exit
fi

# check if repo exist and all under directories work.
echo "Start"
if check_repo_status; then
  echo "Repo exists!"
else
  echo "Some thing went wrong"
  exit
fi

# If no target then the current directory is the target.
if [[ ! -n "$TARGET" ]]; then
  # target_action
  TARGET="$(pwd)"
fi

echo "Target -> $TARGET"
if [[ -d "$TARGET" ]]; then
  # The target is a directory loop over the files
  echo -e "${C_TURQUOISE}Target is the directory: $TARGET $NO_FORMAT"
  find "$TARGET" -type f -name "*.zip" -print0 | while IFS= read -r -d '' zipf; do
    fname=$(basename "$zipf")
    name=$(basename "$zipf" .zip)
    echo -e "\tUnpacking: $fname"
    mkdir -p "$TEMP/$name"
    unzip -oq "$zipf" -d "$TEMP/$name" # -o = overwrite, -q = quiet
  done
  echo ""
  sort_target
elif [[ -f "$TARGET" ]]; then
  # the target is fiel
  echo "$C_TURQUOISE Target is a File $NO_FORMAT"
  unzip -oq "$TARGET" -d "$TEMP/" # -o = overwrite, -q = quiet
  sort_target
fi

# Show the file status table
show_status_table
# Remove the temp directory and its content.
rm -rf "$TEMP"
