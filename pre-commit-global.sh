#!/bin/sh
#

# Copyright (c) 2013 Xiriar Software (http://www.xiriar.com/)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied.
# See the License for the specific language governing permissions and
# limitations under the License.

##
# @file
#
# Git global pre-commit hook
#
# Checks run by this hook:
#  - Uncrustify code style check
#    More info on Uncrustify: http://uncrustify.sourceforge.net/
#  - CppCheck static analysis
#    More info on CppCheck: http://cppcheck.sourceforge.net/
#
# Features:
#  - abort commit when commit does not comply with the style guidelines
#  - create a patch of the proposed code style changes
#  - abort commit when the CppCheck static analysis reports an issue
#
#
# @author     Emil Maskovsky, emil.maskovsky@xiriar.com
# @date       2013/08/18
# @copyright  (c) 2013 Xiriar Software (http://www.xiriar.com/)
#
# Link: https://github.com/xiriar/tools-hooks
#
# Inspired by Uncrustify pre-commit hook, created by David Martin:
# https://github.com/githubbrowser/Pre-commit-hooks/blob/master/pre-commit-uncrustify
##


# Exit and fail on error immediately
set -e

# Source the utility script
. "$(dirname -- "$0")/hook_utils.sh"


# ============================================================================ #
# CONFIGURE
# ---------------------------------------------------------------------------- #
# Do not modify this directly, use "git config [--global]" to configure.
# ============================================================================ #

# The user or company name
#
# Concatenated with " code style" for the informational messages.
COMPANY_NAME="$(git_option "hooks.company" "Xiriar")"

# Count of simultaneous parallel tasks
#
# Can improve performance for large commits (especially merge commits).
PARALLEL_PROC="$(git_option "hooks.parallel" "4" "int")"

# Remove any older results from previous commits
CLEAN_OLD_OUTPUT="$(git_option "hooks.pre-commit.cleanup" "true" "bool")"

# Skip merge commits
#
# Possible motivation:
# - Merge commits can affect a lot of files, can take a long time until the
#   tests pass.
# - Applying code style patches on merges can sometimes cause conflicts when
#   merging back and forth.
# Also aplies to cherry-picks.
SKIP_MERGE="$(git_option "hooks.pre-commit.skipmerge" "false" "bool")"

# Apply the patch to the index automatically
#
# Warning: This can be dangerous (the review of the changes is skipped).
AUTO_FORMAT="$(git_option "hooks.reformat.autoapply" "false" "bool")"

# ---------------------------------------------------------------------------- #
# Uncrustify code style check options
# ---------------------------------------------------------------------------- #

# Path to the Uncrustify binary
UNCRUSTIFY="$(git_option "hooks.uncrustify.path" "$(which uncrustify)" "path")"

# Path to the Uncrustify configuration
UNCRUSTIFY_CONFIG="$(git_option "hooks.uncrustify.config" "$(dirname -- "$(canonicalize_filename "$0")")/uncrustify.cfg" "path")"

# The source code language for Uncrustify
#
# Available values: C, CPP, D, CS, JAVA, PAWN, VALA, OC, OC+.
UNCRUSTIFY_LANGUAGE="$(git_option "hooks.uncrustify.language" "CPP")"

# File types to parse by Uncrustify
UNCRUSTIFY_FILE_TYPES="$(git_option "hooks.uncrustify.filetypes" ".c .h .cc .hh .cpp .hpp .cxx .hxx .inl .cu")"

# ---------------------------------------------------------------------------- #
# CppCheck static analysis options
# ---------------------------------------------------------------------------- #

# Path to the CppCheck binary
CPPCHECK="$(git_option "hooks.cppcheck.path" "$(which cppcheck)" "path")"

# The CppCheck C++ standard
#
# Available values: posix, c89, c99, c11, c++03, c++11.
CPPCHECK_STANDARD="$(git_option "hooks.cppcheck.standard" "c++03")"

# File types to parse
CPPCHECK_FILE_TYPES="$(git_option "hooks.cppcheck.filetypes" ".c .h .cc .hh .cpp .hpp .cxx .hxx .inl .cu")"


# ============================================================================ #
# EXECUTE
# ============================================================================ #

printf "Starting the %s global hook - please wait ...\n" "$COMPANY_NAME"

# Check the merge commits
if [ -f ".git/MERGE_MSG" ]
then
    printf "    > merge detected"
    if [ -n "$SKIP_MERGE" ] && $SKIP_MERGE
    then
        printf "\n... check skipped.\n"
        exit 0
    else
        printf "      (the check can take more time)\n"
    fi
fi

# Needed for the initial commit
if git rev-parse --verify HEAD >/dev/null 2>&1
then
    against=HEAD
else
    # Initial commit: diff against an empty tree object
    against=4b825dc642cb6eb9a060e54bf8d69288fbee4904
fi

# Make sure the config file and executables paths are correctly set
if [ ! -f "$UNCRUSTIFY_CONFIG" ]
then
    printf "Error: uncrustify config file not found.\n"
    printf "Configure by:\n"
    printf "  git config [--global] hooks.uncrustify.config <full_path>\n"
    printf "(the path must be a full absolute path)\n"
    exit 1
fi

if [ ! -x "$UNCRUSTIFY" ]
then
    printf "Error: The Uncrustify executable not found.\n"
    printf "Configure by:\n"
    printf "  git config [--global] hooks.uncrustify.path <full_path>\n"
    printf "(the path must be a full absolute path)\n"
    exit 1
fi

if [ ! -x "$CPPCHECK" ]
then
    printf "Error: The CppCheck executable not found.\n"
    printf "Configure by:\n"
    printf "  git config [--global] hooks.cppcheck.path <full_path>\n"
    printf "(the path must be a full absolute path)\n"
    exit 1
fi

# Check the number of parallel tasks
if [ "$PARALLEL_PROC" -lt 1 ]
then
    printf "Error: Number of parallel tasks set to %s\n" "$PARALLEL_PROC"
    printf "Configure by:\n"
    printf "  git config [--global] hooks.uncrustify.parallel <full_path>\n"
    exit 1
fi

# Create a random filenames for the generated files
prefix="pre-commit"
suffix="$(date +%s)"
uncrustify_patch="/tmp/$prefix-uncrustify-$suffix.patch"
cppcheck_report="/tmp/$prefix-cppcheck-$suffix.report"

# Remove old temporary files (always, even if CLEAN_OLD_OUTPUT not set)
rm -f /tmp/$prefix-*.tmp || true

# Clean up any older dumps from previous runs
#
# Those could remain in the mirror location, if the user aborted the script)
rm -rf /tmp/$prefix-*.dmp/ || true

# Remove any older data
[ -n "$CLEAN_OLD_OUTPUT" ] && $CLEAN_OLD_OUTPUT && rm -f /tmp/$prefix*.patch || true

# Clean the current Uncrustify patch, if it already exists
[ -f "$uncrustify_patch" ] && rm -f "$uncrustify_patch"

# Clean the current CppCheck report, if it already exists
[ -f "$cppcheck_report" ] && rm -f "$cppcheck_report"


# Get the list of modified files
filelist="$(git diff-index --cached --diff-filter=ACMR --name-only $against --)"

# Dump the current index state to a mirror location
#
# This helps to handle partially committed files, and also allows to continue
# working in the current working directory during the run of the script.
mirror="/tmp/$prefix-$suffix.dmp/"
printf "Dumping the current commit index to the mirror location ...\n"

# Only the checked files are dumped, to improve the index dump speed
if [ -n "$filelist" ]
then
    printf "%s\n" "$filelist" | git checkout-index "--prefix=$mirror" --stdin
fi

printf "... index dump done.\n"


# Process a file list in parallel task
process_list() {
    local filelist="$1"
    local task="$2"

    # The Uncrustify patch name for the current task
    local uncrustify_patch_task="/tmp/$prefix-uncrustify-$suffix-$task.tmp"
    # The CppCheck file list name for the current task
    local cppcheck_list_task="/tmp/$prefix-cppcheck-$suffix-$task.tmp"
    #printf "Patch file: $patchname\n"

    # Remove quotes around the filename by "sed", if inserted by the system
    #
    # Done by the system sometimes, if the filename contains special characters,
    # like the quote itself.
    printf "%s\n" "$filelist" | \
        sed -e 's/^"\(.*\)"$/\1/' | \
        while read filename
    do
        # Skip directories
        if [ -d "$filename" ]
        then
            printf "Skipping the directory: %s\n" "$filename"
            continue
        fi

        # Create a list of all files checked by CppCheck according to
        # the $CPPCHECK_FILE_TYPES settings
        if [ ! -n "$CPPCHECK_FILE_TYPES" ] || test_file_ext "$filename" "$CPPCHECK_FILE_TYPES"
        then
            printf "%s\n" "$filename" >> "$cppcheck_list_task"
        fi

        # Ignore the file if we check the file type and the file
        # does not match any of the extensions specified in $UNCRUSTIFY_FILE_TYPES
        if [ -n "$UNCRUSTIFY_FILE_TYPES" ] && ! test_file_ext "$filename" "$UNCRUSTIFY_FILE_TYPES"
        then
            continue
        fi

        printf "Checking file: %s\n" "$filename"

        # Escape special characters in the source filename:
        # - '\': baskslash needs to be escaped
        # - '*': used as matching string => '*' would mean expansion
        #        (curiously, '?' must not be escaped)
        # - '[': used as matching string => '[' would mean start of set
        # - '|': used as sed split char instead of '/', so it needs to be escaped
        #        in the filename
        # printf %s is particularly important if the filename contains the % character
        source_escaped=$(printf "%s" "$filename" | sed -e 's/[\*[|]/\\&/g')

        # Escape special characters in the target filename:
        # Phase 1 (characters escaped in the output diff):
        #     - '\': baskslash needs to be escaped in the output diff
        #     - '"': quote needs to be escaped in the output diff if present inside
        #            of the filename, as it used to bracket the entire filename part
        # Phase 2 (characters escaped in the match replacement):
        #     - '\': baskslash needs to be escaped again for the sed itself
        #            (i.e. double escaping after phase 1)
        #     - '&': would expand to matched string
        #     - '|': used as sed split char instead of '/'
        # printf %s is particularly important if the filename contains the % character
        target_escaped=$(printf "%s" "$filename" | sed -e 's/[\"]/\\&/g' -e 's/[\&|]/\\&/g')

        # Process the source file, create a patch with diff and append it
        # to the complete patch
        #
        # The sed call is necessary to transform the patch from
        #    --- $file timestamp
        #    +++ - timestamp
        # to both lines working on the same file and having a a/ and b/ prefix.
        # Else it could not be applied with 'git apply'.
        "$UNCRUSTIFY" -c "$UNCRUSTIFY_CONFIG" -l "$UNCRUSTIFY_LANGUAGE" -f "$filename" -q -L 2 | \
            diff -u -- "$filename" - | \
            sed -e "1s|--- $source_escaped|--- \"a/$target_escaped\"|" -e "2s|+++ -|+++ \"b/$target_escaped\"|" \
            >> "$uncrustify_patch_task"
    done
}


# Process the files
if [ -n "$filelist" ]
then
    printf "\nPerforming the %s ...\n" "Uncrustify Code Style check"

    printf "Parallel processing in $PARALLEL_PROC threads\n"

    # Need to restore the working directory after work
    working_dir="$(pwd)"

    # Chdir to the mirror location, to consider the partially staged files
    #
    # This also allows to continue working in the current working directory
    # while performing the check.
    cd -- "$mirror"

    # Count the number of filenames in the list
    left=$(printf "%s\n" "$filelist" | wc -l)

    proc=0
    block=0
    first=1
    last=0
    files=""

    i=0
    while [ $i -lt $PARALLEL_PROC ]
    do
        # Remaining processors available
        proc=$(($PARALLEL_PROC-$i))
        # Size of current block
        block=$((($left+$proc-1)/$proc))
        # Last line of the block
        last=$(($first+$block-1))

        # Extract the lines $first-$last from the file list
        files=$(printf "%s\n" "$filelist" | sed -ne "${first},${last}p;${last}q")

        # Process the list block in parallel background task
        process_list "$files" "$i" &

        # Prepare for the next iteration
        first=$(($last+1))
        left=$(($left-$block))
        i=$(($i+1))
    done

    # Wait for all tasks to complete
    wait


    # Concatenate all the partial results from the parallel tasks
    cppcheck_list="/tmp/$prefix-cppcheck-$suffix.tmp"
    i=0
    while [ $i -lt $PARALLEL_PROC ]
    do
        # The Uncrustify partial patches
        if [ -r "/tmp/$prefix-uncrustify-$suffix-$i.tmp" ]
        then
            #printf "Concatenating diff: /tmp/$prefix-uncrustify-$suffix-$i.tmp\n"
            cat "/tmp/$prefix-uncrustify-$suffix-$i.tmp" >> "$uncrustify_patch"
            rm -f "/tmp/$prefix-uncrustify-$suffix-$i.tmp" || true
        fi
        # The CppCheck partial lists
        if [ -r "/tmp/$prefix-cppcheck-$suffix-$i.tmp" ]
        then
            #printf "Concatenating file list: /tmp/$prefix-cppcheck-$suffix-$i.tmp\n"
            cat "/tmp/$prefix-cppcheck-$suffix-$i.tmp" >> "$cppcheck_list"
            rm -f "/tmp/$prefix-cppcheck-$suffix-$i.tmp" || true
        fi
        i=$(($i+1))
    done


    # Only perform the CppCheck analysis, if no Uncrustify patch has been generated
    if [ ! -s "$uncrustify_patch" ]
    then
        printf "Files in this commit comply with the %s code style guidelines.\n" "$COMPANY_NAME"

        printf "\nPerforming the %s ...\n" "CppCheck static analysis"

        # Process the source files by CppCheck
        if [ -s "$cppcheck_list" ]
        then
            "$CPPCHECK" "--std=$CPPCHECK_STANDARD" -j "$PARALLEL_PROC" \
                --enable=warning --enable=performance --enable=portability \
                --enable=style --inconclusive \
                --file-list="$cppcheck_list" 2>"$cppcheck_report"
        fi

        if [ ! -s "$cppcheck_report" ]
        then
            printf "Files in this commit passed the CppCheck static analysis.\n"
        fi
    fi

    # Remove the CppCheck temporary file list
    rm -f -- "$cppcheck_list" || true


    # Restore the working directory
    cd -- "$working_dir"

    # Remove the index dump
    rm -rf -- "$mirror" || true
fi


# Only show first N lines of the patches and reports
nmaxlines=25


# Check if an Uncrustify patch has been generated
test_uncrustify() {

    # If no patch has been generated all is ok, clean up the file stub and exit
    if [ ! -s "$uncrustify_patch" ]
    then
        rm -f "$uncrustify_patch" || true
        return 0
    fi

    # A patch has been created
    printf "\nThe following differences were found between the code to commit "
    printf "and the %s code style guidelines:\n\n" "$COMPANY_NAME"

    cat "$uncrustify_patch" | head -n "$nmaxlines"
    if [ $(wc -l <"$uncrustify_patch") -gt "$nmaxlines" ]
    then
        printf "\n(first %s lines shown)\n" "$nmaxlines"
    fi

    # Check the auto-reformat option
    if [ -n "$AUTO_FORMAT" ] && $AUTO_FORMAT
    then
        # Try to apply the code style changes automatically
        printf "\nAuto-format enabled, trying to apply the patch ...\n"
        if git apply --cached "$uncrustify_patch"
        then
            printf "... patch applied.\n"
            # Try to apply the patch to the working dir too, to avoid conflicts
            # (ignore any errors)
            if ! git apply "$uncrustify_patch" >/dev/null 2>/dev/null
            then
                printf "(application to the working dir failed - working dir left unchanged)\n"
            fi
            rm -f "$uncrustify_patch" || true
            printf "\nFiles in this commit patched to comply with the %s" "$COMPANY_NAME"
            printf " code style guidelines.\n"
            return 0
        fi
        printf "Failed to apply the patch!\n"
    fi

    # The patch wasn't applied automatically - notify the user and abort the commit
    printf "\nYou can apply these changes with:\n  git apply %s\n" "$uncrustify_patch" 
    printf "(needs to be called from the root directory of the repository)\n"
    printf "Aborting commit. Apply changes and commit again or skip the check with"
    printf " --no-verify (not recommended).\n"

    return 1
}


# Check if a CppCheck report has been generated
test_cppcheck() {

    # If no report has been generated all is ok, clean up the file stub and exit
    if [ ! -s "$cppcheck_report" ]
    then
        rm -f "$cppcheck_report" || true
        return 0
    fi

    # The CppCheck static analysis found some problems - notify the user and abort the commit
    printf "\nThe following problems were reported in the code to commit "
    printf "by the CppCheck statis analysis:\n\n"

    cat "$cppcheck_report" | head -n "$nmaxlines"
    if [ $(wc -l <"$cppcheck_report") -gt "$nmaxlines" ]
    then
        printf "\n(first %s lines shown)\n" "$nmaxlines"
    fi

    printf "\nYou can review the problems with:\n  less %s\n" "$cppcheck_report" 
    printf "Aborting commit. Fix the problems and commit again or skip the check with"
    printf " --no-verify (not recommended).\n"

    return 1
}


test_uncrustify
test_cppcheck

# EOF
