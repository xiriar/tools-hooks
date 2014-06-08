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

# Source the utility script
. "$(dirname -- "$0")/hook_utils.sh"


# ============================================================================ #
# CONFIGURE
# ---------------------------------------------------------------------------- #
# Do not modify this directly, use "git config [--global]" to configure.
# ============================================================================ #

# Path to the CppCheck binary
CPPCHECK="$(git_option "hooks.cppcheck.path" "$(which cppcheck)" "path")"

# The C++ standard
#
# Available values: posix, c89, c99, c11, c++03, c++11.
CPP_STANDARD="$(git_option "hooks.cppcheck.standard" "c++03")"

# Remove any older reports from previous commits
CLEAN_OLD_REPORTS="$(git_option "hooks.cppcheck.cleanup" "true" "bool")"

# File types to parse
FILE_TYPES="$(git_option "hooks.cppcheck.filetypes" ".c .h .cc .hh .cpp .hpp .cxx .hxx .inl .cu")"

# Skip merge commits
#
# Possible motivation:
# - Merge commits can affect a lot of files, can take a long time until the
#   tests pass.
# - Applying code style patches on merges can sometimes cause conflicts when
#   merging back and forth.
# Also aplies to cherry-picks.
SKIP_MERGE="$(git_option "hooks.cppcheck.skipmerge" "false" "bool")"


# ============================================================================ #
# EXECUTE
# ============================================================================ #

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

# Make sure the executable path is correctly set
if [ ! -x "$CPPCHECK" ]
then
    printf "Error: The CppCheck executable not found.\n"
    printf "Configure by:\n"
    printf "  git config [--global] hooks.cppcheck.path <full_path>\n"
    printf "(the path must be a full absolute path)\n"
    exit 1
fi

# Create a random filename to store our generated report
prefix="pre-commit-cppcheck"
suffix="$(date +%s)"
report="/tmp/$prefix-$suffix.report"

# Clean up any older dumps from previous runs
#
# Those could remain in the mirror location, if the user aborted the script)
rm -rf /tmp/$prefix-*.dmp/ || true

# Remove any older uncrustify patches
[ -n "$CLEAN_OLD_REPORTS" ] && $CLEAN_OLD_REPORTS && rm -f /tmp/$prefix*.report || true

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


# Run the CppCheck static analysis
if [ -n "$filelist" ]
then

    # Need to restore the working directory after work
    working_dir="$(pwd)"

    # Chdir to the mirror location, to consider the partially staged files
    #
    # This also allows to continue working in the current working directory
    # while performing the check.
    cd -- "$mirror"

    # Process the source files
    "$CPPCHECK" "--std=$CPP_STANDARD" --enable=warning --inconclusive \
        --enable=performance --enable=portability --enable=style \
        . 2>"$report"

    # Restore the working directory
    cd -- "$working_dir"

    # Remove the index dump
    rm -rf -- "$mirror" || true
fi


# If no report has been generated all is ok, clean up the file stub and exit
if [ ! -s "$report" ]
then
    printf "Files in this commit passed the CppCheck static analysis.\n"
    rm -f "$report" || true
    exit 0
fi

# The CppCheck static analysis found some problems - notify the user and abort the commit
printf "\nThe following problems were reported in the code to commit "
printf "by the CppCheck statis analysis:\n\n"

# only show first N lines of the report
nmaxlines=25
cat "$report" | head -n "$nmaxlines"
if [ $(wc -l <"$report") -gt "$nmaxlines" ]
then
    printf "\n(first %s lines shown)\n" "$nmaxlines"
fi

printf "\nYou can review the problems with:\n  less %s\n" "$report" 
printf "Aborting commit. Fix the problems and commit again or skip the check with"
printf " --no-verify (not recommended).\n"

exit 1

# EOF
