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
# Test the default Uncrustify configuration
#
#
# @author     Emil Maskovsky, emil.maskovsky@xiriar.com
# @date       2014/06/19
# @copyright  (c) 2014 Xiriar Software (http://www.xiriar.com/)
##


# Exit and fail on error immediately
set -e

# Absolute path to the root of the Git repository
ROOTPATH="$(git rev-parse --show-toplevel)"

# Source the utility script
. "$ROOTPATH/hook_utils.sh"


# ============================================================================ #
# CONFIGURE
# ---------------------------------------------------------------------------- #
# Do not modify this directly, use "git config [--global]" to configure.
# ============================================================================ #

# Path to the Uncrustify binary
UNCRUSTIFY="$(git_option "hooks.uncrustify.path" "$(which uncrustify)" "path")"

# Path to the Uncrustify configuration
UNCRUSTIFY_CONFIG="$ROOTPATH/uncrustify.cfg"


# ============================================================================ #
# EXECUTE
# ============================================================================ #

# Make sure the config file and executables paths are correctly set
if [ ! -f "$UNCRUSTIFY_CONFIG" ]
then
    printf "Error: uncrustify config file not found.\n"
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

# Create a random filenames for the generated files
prefix="pre-commit"
suffix="$(date +%s)"
uncrustify_patch="/tmp/$prefix-uncrustify-test-$suffix.patch"

# Remove any older data
rm -f /tmp/$prefix-uncrustify-test*.patch || true


# Check the test file and compare it with the reference result
SCRIPT_PATH="$(dirname -- "$(canonicalize_filename "$0")")"
"$UNCRUSTIFY" -c "$UNCRUSTIFY_CONFIG" -l "CPP" -f "$SCRIPT_PATH/test_uncrustify.cpp" -q -L 2 | \
    diff -u -- "$SCRIPT_PATH/ref/test_uncrustify.cpp" - | \
    sed -e "1s|--- $SCRIPT_PATH/ref/test_uncrustify\.cpp|--- a/tests/ref/test_uncrustify.cpp|" -e "2s|+++ -|+++ b/tests/ref/test_uncrustify.cpp|" \
    > "$uncrustify_patch"

# If no patch has been generated all is ok, clean up the file stub and exit
if [ ! -s "$uncrustify_patch" ]
then
    printf "\nThe Uncrustify config file test passed.\n"
    rm -f "$uncrustify_patch" || true
    exit 0
fi

# A patch has been created - notify the user
printf "\nThe following differences were found between the Uncrustify result "
printf "and the reference file:\n\n"

cat "$uncrustify_patch"

printf "\nYou can update the reference data with:\n  git apply %s\n" "$uncrustify_patch" 
printf "(needs to be called from the root directory of the repository)\n"

exit 1

# EOF
