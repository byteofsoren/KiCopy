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
# FOOTPRINTS="$REPO/footprints"
# SYMBOLS="$REPO/symbols"
VISUALFILES="$REPO/3d"
DESIGNBLOCK="$REPO/design_blocks"

TARGET=""
CHECKTARGET=False
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

export fzf_sidebar_files fzf_sidebar_prompt
OPTIONS=$(getopt -o t:c --long target:,check,create:,help,type: -- "$@")
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
#   action=move_to_repo_cehck "$REPO/TVS.pretty" file_name
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
  echo "Move comelete pretty libraries"
  while IFS= read -r -d '' file; do
    # process "$file"
    # fname is the name of the file excluding the path to the file
    local fname=""
    fname=$(basename "$file")

    # Move to repo check checks if there is going to be any conflicts moving the file.
    # local acction
    # acction=move_to_repo_cehck "$FOOTPRINTS" fname

    # If CHECKTARGET is false then move the files from source to target dir.
    if [[ $CHECKTARGET == false ]]; then
      echo "Move the files to $REPO"
      # echo "mv $file $FOOTPRINTS/$fname"
      # mv "$file" "$FOOTPRINTS/$fname"
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
    # move_to_repo_cehck "$FOOTPRINTS" fname
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
    # move_to_repo_cehck "$SYMBOLS" fname
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
    # move_to_repo_cehck "$VISUALFILES" fname
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

create_new_pretty() {
  newdirname="${REPO}/${1}.pretty"
  while true; do
    if [[ -d "$newdirname" ]]; then
      echo "$newdirname already exists"
      echo "Change name or Skip C/S"
      lecal change_or_skip
      read -n 1 -r change_or_skip
      case "$change_or_skip" in
      c | C)
        read -r newdirname
        continue
        ;;
      s | S)
        return 2
        ;;
      *)
        continue
        ;;
      esac
    fi
    break
    # read -r newdirname
  done
  mkdir -p "$newdirname"
}

# ================================================
# FZF side preview function called by --preview
# Is called by the --preview in fzf
# External:
#   fzf_sidebar_files
#   fzf_sidebar_prompt
# ================================================
fzf_side_preview() {
  # fzf passes the FULL original line (with tabs) as $1 when we use {}
  local full="$1"

  local type data show
  # local -a files_arr=()
  local fzf_width=${FZF_PREVIEW_COLUMNS:-80}

  # echo "Test"
  # Split the line on tabs
  IFS=$'\t' read -r type data show <<<"$full"
  IFS=$'\t' read -ra files_arr <<<"$fzf_sidebar_files"
  echo "$show" >/dev/null
  echo -e "\e[38;5;45m$fzf_sidebar_prompt\e[0m"
  for file in "${files_arr[@]}"; do
    printf "  %s\n" "$file"
  done
  for ((i = 0; i < fzf_width; i++)); do
    printf "_"
  done
  echo ""

  case "$type" in
  directory | file | pretty) # adjust these names to whatever you actually use
    # Show directory tree or ls with colors
    tree -C "$data" 2>/dev/null ||
      ls --color=always -l "$data" 2>/dev/null ||
      echo -e "\e[33mCannot preview $data\e[0m"
    ;;
  command)
    if [[ "$data" == new ]]; then
      echo -e "\e[32mCreate new pretty directory for components\e[0m"
    elif [[ "$data" == skip || "$data" == skipp ]]; then # accept both spellings
      echo -e "\e[33mSkip placement of component\e[0m"
    else
      echo -e "\e[33mNo preview available for this action\e[0m"
      echo -e "\e[90m(type: $type | data: $data)\e[0m"
    fi
    ;;
  *)
    echo -e "\e[32mCreate new pretty directory for components?\e[0m"
    ;;
  esac
}

# ================================================
# Pretty menu
# Takes a list, prompt and shows the menu using fzf.
# The input list is a list of tab separated strings like this:
# "type\tdata\show"
#  Inputs:
#    $1 selected string
# ================================================
show_menu() {
  echo "menu"
  local -n selected_pretty=$1
  # Get all pretty libraries in REPO
  local -a pretty_menu_array=()
  # Set new and skipp options.
  # pretty_menu_array+=("$(printf "%b\n" "command\tnew\t${C_GREEN}New library...$NO_FORMAT")")
  pretty_menu_array+=("$(printf "%b\n" "command\tskipp\t${C_GREEN}Skipp$NO_FORMAT")")

  # This lists .pretty files in the repo to where to move the components
  # Example:
  #   The components:
  #   - LIB_TVS4685463.kicad_mod
  #   - LIB_TVS4685463.kicad_sym
  #   Show the menu select:
  #   - $REPO/TVS.pretty
  #   Return a recomendation to move the
  #   .kicad_mod and .kicad_sym to $REPO/TVS.pretty
  while IFS= read -r -d '' pretty; do
    # base_name=$(basename $pretty)
    local dir_name
    dir_name=$(basename "$pretty" .pretty)
    pretty_menu_array+=("$(printf "%b\n" "pretty\t$pretty\t${C_TURQUOISE}$dir_name${NO_FORMAT}")")
  done < <(find "$REPO" \( -type d -name "*.pretty" \) -print0)

  selected_pretty=$(
    printf "%s\n" "${pretty_menu_array[@]}" |
      fzf --ansi \
        --prompt="Select action: " \
        --delimiter '\t' \
        --with-nth 3.. \
        --preview 'bash -c "fzf_side_preview {}"' \
        --preview-window=right:50%:border:wrap \
        --bind 'ctrl-/:toggle-preview' # optional: Ctrl+/ to hide/show preview
  )
  selected_exit_status=$?
  # 0 Normal exit
  # 1 No match
  # 2 Error
  if [[ $selected_exit_status == 1 ]]; then
    selected_pretty="newpretty\t$selected_pretty\tnewpretty"
  fi

  echo "$selected_pretty remove warning message" >>/dev/null
}

# ================================================
# Move to Repo
# Arguments:
#   $1 file to be be moved to repo path.
#   $2 repo path ie "$REPO/xxxx/TVS.pretty"
# Returns:
#   ERROR if the move_to_repo_cehck returns ERROR
#   IGNOREFILE if move_to_repo_cehck returns IGNOREFILE
# Example:
#   $ move_to_repo "/tmp/xxxx/LIB_TVS4685463.zipd/xxxx.kicadx" "$REPO/TVS/."
# ================================================
move_to_repo() {
  local file=$1
  local repo_path=$2
  local base_filename
  local move_error
  base_filename=$(basename "$file")
  move_to_repo_cehck "$REPO/repo_path" base_filename
  move_error=$?
  if [[ "$move_error" == "$ERROR" ]]; then
    return "$ERROR"
  elif [[ "$move_error" == "$IGNOREFILE" ]]; then
    echo "$base_filename ignored"
    return "$IGNOREFILE"
  fi
  # Move the file=/tmp/xxxx/*.kicadx to repo_path="$REPO/TVS.pretty/."
  if [[ -d "$repo_path" ]]; then
    mv "$file" "$repo_path/."
  fi
}

# ================================================
# Select type menu
# When moving files in to $REPO you some times
# do not want to move all of them.
# Symbols
# Example
#   select_type_menu "$TEMP/LIB_TVS4685463.zipd" "$REPO/TVS diode.pretty"
# ================================================
select_type_menu() {
  local temp_path=$1
  local repo_path=$2
  local what_arr=("All files" "Symbols" "Footprints" "3D files")
  local selected=()
  local all_files=false
  # Sanitace the output
  if [[ ! -d "$repo_path" || ! -d "$temp_path" ]]; then
    echo "Path provided did not exists"
    return "$ERROR"
  fi
  # Select ether one in $what_arr.
  while true; do
    while IFS= read -r -d '' item; do
      [[ -n "$item" ]] && selected+=("$item")
      [[ "$item" = "All files" ]] && all_files=true && break
    done < <(printf '%s\0' "${what_arr[@]}" | fzf --multi --read0 --print0 --prompt "Select with [Tab] what to include")
    if ((${#selected[@]})); then
      break
    else
      echo "Please select one"
    fi
  done

  # For all files its easy
  if $all_files; then
    # Move all files to repo
    while IFS= read -r -d '' file; do
      # file="/tmp/xxxx/LIB_TVS4685463.zipd"
      #   $ move_to_repo "/tmp/xxxx/LIB_TVS4685463.zipd/xxxx.kicadx" "$REPO/TVS/."
      local returnopt
      move_to_repo "$file" "$repo_path/."
      returnopt=$?
      if [[ "$returnopt" == "$ERROR" ]]; then
        return "$ERROR"
      fi

    done < <(find "$temp_path" -type f -iregex \
      '.*\.\(kicad_mod\|mod\|kicad_sym\|lib\|dcm\|wrl\|step\|stp\|idf\|stl\|ply\|glb\|brep\|xao\)$' -print0)
  elif [[ ${#selected[@]} -gt 0 ]]; then
    echo ""
    # Move for each selected element in selected
    for select in "${selected[@]}"; do
      echo "$select"
      if [[ -z "$select" || "$select" == "All files" ]]; then
        continue
      fi
      # For each filetype:
      # "Symbols" "Footprints" "3D files"
      if [[ "$select" == "Symbols" ]]; then
        echo ""
      elif [[ "$select" == "Footprints" ]]; then
        echo ""
      elif [[ "$select" == "3D files" ]]; then
        echo ""

      fi

    done

  fi

}

# ================================================
# select sublibrary in repo by using fzf
# Example:
#   $ move_to_repo '$TEMP/component.zipd'
#   Opens a fzf menu where you can select .pretty library
#   in $REPO to where the files are going to be placed
# ================================================
select_sublib_in_repo() {
  echo "move to repo with fzf"
  local movetarget
  movetarget="$1"

  # The target was a file
  # Collect all kicad files
  fzf_sidebar_files=""
  mapfile -d '' -t fzf_sidebar_files < <(find "$movetarget" -type f -iregex \
    '.*\.\(kicad_mod\|mod\|kicad_sym\|lib\|dcm\|wrl\|step\|stp\|idf\|stl\|ply\|glb\|brep\|xao\)$' -print0)
  fzf_sidebar_prompt="Files from $movetarget"
  # Show menu needs a return value and that is done in selected_pretty
  local selected_pretty
  show_menu selected_pretty
  # Store the result from show_menu as type, data and show.
  # The show is what was shown in the menu.
  # Data is the selected or new pretty library.
  # Type is what type of command is selected. ie: newpretty, command, pretty
  local type data show error
  IFS=$'\t' read -r type data show <<<"$selected_pretty"
  if [[ "$type" == "command" && "$data" == "new" ]]; then
    local newdirname
    read -r -p "New library name: " newdirname
    create_new_pretty "$newdirname"
  elif [[ "$type" == "newpretty" && -n "$data" ]]; then
    echo "Create new pretty library?"
    create_new_pretty "$data"
  elif [[ "$type" == "command" && "$data" == "skipp" ]]; then
    echo "Skipp this component"
    return
  else
    echo "Error"
    return "$ERROR"
  fi

}

show_help() {
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
}

# ================================================
# Mani function
# ================================================
main() {
  echo "Main"
  # Move the footprints/symbols to REPO
  if [[ -f "$TARGET" ]]; then
    # unzip file
    unzip "$TARGET" -d "$TEMP"
    move_to_repo "$TEMP"

  elif [[ -d "$TARGET" ]]; then
    # Unzip a directorie of zip files.
    #
    while IFS= read -r -d '' zipfile; do
      echo "Unziping $zipfile"
      local zipd
      zipd="$TEMP/$zipfile.zipd"
      mkdir -p "$zipd"
      unzip "$TARGET" -d "$zipd"
      move_to_repo "$zipd"
    done < <(find "$TEMP" \( -type f -name "*.zip" \) -print0)
  fi

  # move_to_repo 'TEMP/component.zipd'
  # How to use:
  #   action=move_to_repo_cehck "$REPO/mydir" file_name
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
    show_help
    exit
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

# Verify that $TAREGT is not empty!
if [[ -n "$TARGET" ]]; then
  main
fi
# Show the file status table
# show_status_table
# Remove the temp directory and its content.
rm -rf "$TEMP"
