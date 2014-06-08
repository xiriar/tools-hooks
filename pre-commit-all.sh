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
# Git pre-commit hook that runs multiple hooks specified in $HOOKS
#
# @author     Emil Maskovsky, emil.maskovsky@xiriar.com
# @date       2013/11/10
# @copyright  (c) 2013 Xiriar Software (http://www.xiriar.com/)
##


# Exit and fail on error immediately
set -e

# Source the utility script
. "$(dirname -- "$0")/hook_utils.sh"


# ============================================================================ |
# CONFIGURE
# ---------------------------------------------------------------------------- |
# Do not modify this directly, use "git config [--global]" to configure.
# ============================================================================ |

# The list of available pre-commit hooks
#
# Do not edit here, configure by:
#   "git config [--global] hooks.pre-commit.<hook> enabled/disabled"
HOOKS="default cppcheck"


# ============================================================================ #
# EXECUTE
# ============================================================================ #

# Absolute path to this script, e.g. /home/user/bin/foo.sh
SCRIPT="$(canonicalize_filename "$0")"

# Absolute path this script is in, thus /home/user/bin
SCRIPTPATH="$(dirname -- "$SCRIPT")"

for hook in $HOOKS
do
    # Check if the hook is enabled
    if [ "$(git_option "hooks.pre-commit.$hook" "enable")" = "enable" ]
    then
        echo "Running hook: $hook"
        # Run hook if it exists and is executable
        #
        # If it returns with nonzero exit with 1 and thus abort the commit.
        if [ -x "$SCRIPTPATH/pre-commit-$hook.sh" ]
        then
            "$SCRIPTPATH/pre-commit-$hook.sh" || exit 1
        else
            echo "Error: file pre-commit-$hook.sh not found."
            echo "Aborting commit. Make sure the hook is in $SCRIPTPATH and executable."
            echo "You can disable the hook by setting:"
            echo "  git config --global hooks.pre-commit.$hook disable"
            echo "You can skip all pre-commit hooks with --no-verify (not recommended)."
            exit 1
        fi
    fi
done

# EOF
