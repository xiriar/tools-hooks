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
# Git pre-commit hook that runs an Uncrustify stylecheck
#
# Features:
#  - abort commit when commit does not comply with the style guidelines
#  - create a patch of the proposed style changes
#
# More info on Uncrustify: http://uncrustify.sourceforge.net/
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


# ============================================================================ #
# CONFIGURE
# ============================================================================ #

# The user or company name
#
# Concatenated with " code style" for the informational messages.
#COMPANY_NAME=Company
COMPANY_NAME=Xiriar

# Path to the Uncrustify binary
#UNCRUSTIFY="/usr/bin/uncrustify"
UNCRUSTIFY="uncrustify"

# Path to the Uncrustify configuration
#CONFIG="$HOME/.config/uncrustify.cfg"
CONFIG="$HOME/.config/uncrustify.cfg"

# The source code language
#
# Available values: C, CPP, D, CS, JAVA, PAWN, VALA, OC, OC+.
#SOURCE_LANGUAGE="CPP"
SOURCE_LANGUAGE="CPP"

# Remove any older patches from previous commits
#CLEAN_OLD_PATCHES=true
CLEAN_OLD_PATCHES=true

# File types to parse
#FILE_TYPES=".c .h .cpp .hpp"
FILE_TYPES=".c .h .cpp .hpp"

# Skip merge commits
#
# Possible motivation:
# - Merge commits can affect a lot of files, can take a long time until the
#   tests pass.
# - Applying code style patches on merges can sometimes cause conflicts when
#   merging back and forth.
# Also aplies to cherry-picks.
#SKIP_MERGE=true

# Apply the patch to the index automatically
#
# Warning: This can be dangerous (the review of the changes is skipped).
#AUTO_APPLY=true

# Count of simultaneous parallel tasks
#
# Can improve performance for large commits (especially merge commits).
#PARALLEL_PROC=4
PARALLEL_PROC=4


# ============================================================================ #
# EXECUTE
# ============================================================================ #

# Source the utility script
source "$(dirname "$0")/hook_utils.sh"

printf "Starting the $COMPANY_NAME code style check - please wait ...\n"

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

# Make sure the config file and executable are correctly set
if [ ! -f "$CONFIG" ]
then
    printf "Error: uncrustify config file not found.\n"
    printf "Set the correct path in $(canonicalize_filename "$0").\n"
    exit 1
fi

# Create a random filename to store our generated patch
prefix="pre-commit-uncrustify"
suffix="$(date +%s)"
patch="/tmp/$prefix-$suffix.patch"

# Remove old temporary files (always, even if CLEAN_OLD_PATCHES not set)
rm -f /tmp/$prefix-stage* /tmp/$prefix-temp*

# Remove any older uncrustify patches
[ -n "$CLEAN_OLD_PATCHES" ] && $CLEAN_OLD_PATCHES && rm -f /tmp/$prefix*.patch

# Clean the current patch, if it already exists
[ -f "$patch" ] && rm -f "$patch"


# Create one patch containing all changes to the files
create_patch() {

    printf "Parallel processing in $PARALLEL_PROC threads\n"

    git diff-index --cached --diff-filter=ACMR --name-only $against -- | \
    (
        # Prepare file lists for the particular threads
        local nproc=0
        while read filename
        do
            # Ignore the file if we check the file type and the file
            # does not match any of the extensions specified in $FILE_TYPES
            if [ -n "$FILE_TYPES" ] && ! test_file_ext "$filename" "$FILE_TYPES"
            then
                continue
            fi

            # Skip directories
            if [ -d "$filename" ]
            then
                printf "Skipping the directory: $filename\n"
                continue
            fi

            # We want the trailing newline
            files[$nproc]="${files[$nproc]}$filename
"

            nproc=$(($nproc+1))
            [ "$nproc" -eq "$PARALLEL_PROC" ] && nproc=0

        done

        #printf "Listing done.\n"
        #printf "%s---\n" "${files[@]}"

        # Process the prepared lists
        for (( i=0; i < $PARALLEL_PROC; i++ ))
        do
            #printf "Check list:\n${files[$i]}"
            # Run the tasks in parallel background threads
            process_list "${files[$i]}" "/tmp/$prefix-temp-$suffix-$i.tmp" &
        done

        # Wait for all tasks to complete
        wait
    )
}


# Process a file list
process_list() {
    local filelist=$1
    local patchname=$2
    #printf "Patch file: $patchname\n"

    for filename in $filelist
    do
        process_file "$filename" "$patchname"
    done
}


# Process a single file
process_file() {
    local filename=$1
    local patchname=$2
    printf "Checking file: $filename\n"

    # Save the file which is in the staging area
    #
    # This is to check the currently staged status
    # (might it be a partiall commit).
    local stage="/tmp/$prefix-stage-$suffix-${filename//[\/\\]/-}"
    git show ":0:$filename" >"$stage"

    # Process the source file, create a patch with diff and append it
    # to the complete patch
    #
    # The sed call is necessary to transform the patch from
    #    --- $file timestamp
    #    +++ - timestamp
    # to both lines working on the same file and having a a/ and b/ prefix.
    # Else it could not be applied with 'git apply'.
    "$UNCRUSTIFY" -c "$CONFIG" -l "$SOURCE_LANGUAGE" -f "$stage" -q -L 2 | \
        diff -u "$stage" - | \
        sed -e "1s|--- $stage|--- a/$filename|" -e "2s|+++ -|+++ b/$filename|" \
        >> "$patchname"

    # Remove the temporary file
    rm -f "$stage"
}


# Create the patch
create_patch


# Concatenate all the partial patch lists
for (( i=0; i < $PARALLEL_PROC; i++ ))
do
    if [ -r "/tmp/$prefix-temp-$suffix-$i.tmp" ]
    then
        #printf "Concatenating diff: /tmp/$prefix-$suffix-$i.patch.tmp\n"
        cat "/tmp/$prefix-temp-$suffix-$i.tmp" >> "$patch"
        rm -f "/tmp/$prefix-temp-$suffix-$i.tmp"
    fi
done


# If no patch has been generated all is ok, clean up the file stub and exit
if [ ! -s "$patch" ]
then
    printf "Files in this commit comply with the $COMPANY_NAME code style guidelines.\n"
    rm -f "$patch"
    exit 0
fi

# A patch has been created
printf "\nThe following differences were found between the code to commit "
printf "and the $COMPANY_NAME code style guidelines:\n\n"

cat "$patch"

# Check the auto-apply option
if [ -n "$AUTO_APPLY" ] && $AUTO_APPLY
then
    # Try to apply the changes automatically
    printf "\nAuto-apply enabled, trying to apply the patch ...\n"
    if git apply --cached "$patch"
    then
        printf "... patch applied.\n"
        # Try to apply the patch to the working dir too, to avoid conflicts
        # (ignore any errors)
        if ! git apply "$patch" >/dev/null 2>/dev/null
        then
            printf "(application to the working dir failed - working dir left unchanged)\n"
        fi
        rm -f "$patch"
        printf "\nFiles in this commit patched to comply with the $COMPANY_NAME"
        printf " code style guidelines.\n"
        exit 0
    fi
    printf "Failed to apply the patch!\n"
fi

# The patch wasn't applied automatically - notify the user and abort the commit
printf "\nYou can apply these changes with:\n  git apply $patch\n"
printf "(needs to be called from the root directory of the repository)\n"
printf "Aborting commit. Apply changes and commit again or skip the check with"
printf " --no-verify (not recommended).\n"

exit 1

# EOF
