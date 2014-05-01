#!/bin/sh
#

# Copyright (c) 2014 Xiriar Software (http://www.xiriar.com/)
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
# Git pre-commit hook that runs an CppCheck static analysis
#
# Features:
#  - abort commit when the CppCheck static analysis reports an issue
#
# More info on CppCheck: http://cppcheck.sourceforge.net/
#
# @author     Emil Maskovsky, emil.maskovsky@xiriar.com
# @date       2014/05/01
# @copyright  (c) 2014 Xiriar Software (http://www.xiriar.com/)


# Exit and fail on error immediately
set -e


# ============================================================================ #
# CONFIGURE
# ============================================================================ #

# Path to the CppCheck binary
#CPPCHECK="/usr/bin/cppcheck"
CPPCHECK="cppcheck"

# The C++ standard
#
# Available values: posix, c89, c99, c11, c++03, c++11.
#CPP_STANDARD="c++03"
CPP_STANDARD="c++03"

# Remove any older reports from previous commits
#CLEAN_OLD_REPORTS=true
CLEAN_OLD_REPORTS=true

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


# ============================================================================ #
# EXECUTE
# ============================================================================ #

# Source the utility script
. "$(dirname -- "$0")/hook_utils.sh"

printf "Starting the CppCheck static analysis - please wait ...\n"

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

# Create a random filename to store our generated report
prefix="pre-commit-cppcheck"
suffix="$(date +%s)"
report="/tmp/$prefix-$suffix.report"

# Remove old temporary files (always, even if CLEAN_OLD_REPORTS not set)
rm -f /tmp/$prefix-stage*

# Remove any older uncrustify patches
[ -n "$CLEAN_OLD_REPORTS" ] && $CLEAN_OLD_REPORTS && rm -f /tmp/$prefix*.report

# Clean the current report, if it already exists
[ -f "$report" ] && rm -f "$report"

# Run the CppCheck static analysis
git diff-index --cached --diff-filter=ACMR --name-only $against -- | \
    sed -e 's/^"\(.*\)"$/\1/' | \
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
        printf "Skipping the directory: %s\n" "$filename"
        continue
    fi

    printf "Checking file: %s\n" "$filename"

    # Save the file which is in the staging area
    #
    # This is to check the currently staged status
    # (might it be a partiall commit).
    stage="/tmp/$prefix-stage-$suffix-${filename//[\/\\]/-}"
    git show ":0:$filename" >"$stage"

    # Process the source file
    "$CPPCHECK" "--std=$CPP_STANDARD" -q --enable=warning --inconclusive \
        --enable=performance --enable=portability --enable=style \
        "$stage" >>"$report" 2>>"$report"

    # Remove the temporary file
    rm -f "$stage"
done

# If no report has been generated all is ok, clean up the file stub and exit
if [ ! -s "$report" ]
then
    printf "Files in this commit passed the CppCheck static analysis.\n"
    rm -f "$report"
    exit 0
fi

# The CppCheck static analysis found some problems - notify the user and abort the commit
printf "\nThe following problems were reported in the code to commit "
printf "by the CppCheck statis analysis:\n\n"

cat "$report"

printf "\nYou can review the problems with:\n  less %s\n" "$report" 
printf "Aborting commit. Fix the problems and commit again or skip the check with"
printf " --no-verify (not recommended).\n"

exit 1

# EOF
