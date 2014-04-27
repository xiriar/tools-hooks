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
# Git hook utility functions
#
# @author     Emil Maskovsky, emil.maskovsky@xiriar.com
# @date       2013/11/10
# @copyright  (c) 2013 Xiriar Software (http://www.xiriar.com/)
##


##
# Canonicalize by recursively following every symlink in every component of the
# specified filename.  This should reproduce the results of the GNU version of
# readlink with the -f option.
#
# Reference: http://stackoverflow.com/questions/1055671/how-can-i-get-the-behavior-of-gnus-readlink-f-on-a-mac
canonicalize_filename () {
    local target_file=$1

    local physical_directory=""
    local result=""

    # Need to restore the working directory after work
    pushd "$(pwd)" > /dev/null

    cd -- "$(dirname -- "$target_file")"
    target_file=$(basename -- "$target_file")

    # Iterate down a (possible) chain of symlinks
    while [ -L "$target_file" ]
    do
        target_file=$(readlink -- "$target_file")
        cd -- "$(dirname -- "$target_file")"
        target_file=$(basename -- "$target_file")
    done

    # Compute the canonicalized name by finding the physical path
    # for the directory we're in and appending the target file
    physical_directory=$(pwd -P)
    result="$physical_directory/$target_file"

    # Restore the working directory
    popd > /dev/null

    echo "$result"
}


##
# Check whether the given file name matches any extension in the given list
test_file_ext() {
    local filename="$1"
    local filetypes="$2"

    local filetype
    for filetype in $filetypes
    do
        # Try to remove the filetype pattern from the end of the filename
        #
        # If the filename matches the filetype (extension), the extension is
        # removed (and the processed filename is then different from the
        # original filename).
        # This should work in all POSIX compatible shells.
        [ "$filename" != "${filename%$filetype}" ] && return 0
    done

    # The filename extension does not match any extension off the list
    return 1
}


# EOF
