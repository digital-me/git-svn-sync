# -*- mode: Shell-script-*-
#!/usr/bin/bash
#
# Author: Mario Fernandez
#
# Syncs git repository with subversion, using an extra git client.
#
# The client is a clone of the git repo. It has two branches:
#  - master: It is sync'ed with the git repo. Should always
#            fast-forward.
#  - GIT_SVN_SYNC_BRANCH: Sync'ed with SVN (via git-svn). Noone else
#            can write to svn.
#
# The changes from the git repo are pulled into master, and then
# merged to the svn sync branch. This branch is then synchronized with
# subversion.
#
# Required environment variabless:
#  - GIT_SCRIPTS: directory where the git sync scripts are located
#  - GIT_SVN_SYNC_BASE: directory where the sync repositories are
# stored.
#
# Optional environment variables:
#  - GIT_SVN_SYNC_EMAIL: email to send error reports to
#  - GIT_SVN_SYNC_BRANCH: name of the branch that is synchronized with
#  - GIT_SVN_AUTHORS: authors-file option (default none)
# subversion (default = svn-sync).
#  - GIT_SVN_USER: SVN username to overwrite the configuration property.
#  - GIT_SVN_PASSWORD: SVN password to overwrite the configuration property.
#  - GIT_SVN_VERBOSE: Set to 1 to decrease and 0 to silent Git SVN command verbosity (default 2).
#
# Usage: git-sync-with-svn.sh project_name

if [ -z "${GIT_SCRIPTS}" ] || [ -z "${GIT_SVN_SYNC_BASE}" ] ; then
    echo "The following variables are required for the synchronization to work: GIT_SCRIPTS GIT_SVN_SYNC_BASE"
    exit 1
fi

# Set optional variables
: ${GIT_SVN_SYNC_BRANCH:="svn-sync"}
[ -z "${GIT_SVN_AUTHORS}" ] || GIT_SVN_AUTHORS="--authors-file=${GIT_SVN_AUTHORS} --add-author-from --use-log-author"
: ${GIT_SVN_USER:=""}
: ${GIT_SVN_PASSWORD:=""}
: ${GIT_SVN_VERBOSE:=2}

destination="${GIT_SVN_SYNC_EMAIL}"
project="${1?No project provided}"
location="${GIT_SVN_SYNC_BASE}/${project}"

if [ ! -d "$location" ] ; then
    echo "The folder where the synchronization repository is supposed to be does not exist"
    exit 1
fi

# Prepare user option if required
[ -z "${GIT_SVN_USER}" ] || GIT_SVN_USER_OPT="--username ${GIT_SVN_USER}"

# Set verbosity if required
[ ${GIT_SVN_VERBOSE} -eq 2 ] GIT_SVN_VOPT="--verbose"
[ ${GIT_SVN_VERBOSE} -eq 0 ] GIT_SVN_VOPT="--quiet"

unset GIT_DIR
cd "$location"

report () {
    echo $1
    [ -z "${destination}" ] || sh "${GIT_SCRIPTS}/report-error.sh" "$destination" "$project" "$1"
}

# Get changes from git repository
echo "Getting changes from git repository"
git checkout master || { report "Could not switch to master" ; exit 1; }

if [ -n "$(git status --porcelain)" ] ; then
    echo "Workspace is dirty. Clean it up (i.e with git reset --hard HEAD) before continuing"
    exit 1
fi

git pull --ff-only origin master || { report "Could not pull changes from git repository" ; exit 1; }

# Synchronize with SVN
echo "Synchronizing with SVN"
git checkout ${GIT_SVN_SYNC_BRANCH} || { report "Could not switch to sync branch" ; exit 1; }
echo "Pulling any SVN changes"
{ [ -z "${GIT_SVN_PASSWORD}" ] || echo "${GIT_SVN_PASSWORD}"; } | \
git svn rebase ${GIT_SVN_AUTHORS} ${GIT_SVN_USER_OPT} ${GIT_SVN_VOPT} || { report "Could not rebase SVN changes" ; exit 1; }
# In case of conflicts, take the master, as we are sure that this is
# the correct branch
git merge -Xtheirs master || { report "Could not merge changes into sync branch" ; exit 1; }
{ [ -z "${GIT_SVN_PASSWORD}" ] || for n in {1..3}; do echo "${GIT_SVN_PASSWORD}"; done; } | \
git svn dcommit ${GIT_SVN_AUTHORS} ${GIT_SVN_USER_OPT} ${GIT_SVN_VOPT} || { report "Could not send changes to svn repository" ; exit 1; }
