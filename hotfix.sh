#!/bin/sh

usage() {
  echo "usage: ./hotfix.sh [start / finish]"
  echo "start => Init a new hotfix"
  echo "finish => Merge the hotfix to master and dev and delete the branch"
}

getPackageVersion() {
  PACKAGE_VERSION=$(cat ./package.json \
  | grep version \
  | head -1 \
  | awk -F: '{ print $2 }' \
  | sed 's/[",]//g' \
  | xargs)
}

incrementPatchVersion() {
  git checkout "${1}"
  npm version patch --no-git-tag-version
  getPackageVersion
  git add ./package.json
  git commit -m "Updating patch version to ${PACKAGE_VERSION}" -- ./package.json
  git push
}

checkUnstagedChanges() {
  echo "Checking unstaged changes..."
  git diff-index --quiet HEAD --
  if [ $? -ge 1 ]
  then
    echo "There is some unstaged changes..."
    echo "Please, commit your changes before creating a new hotfix."
    exit 2
  fi
}

checkMergeConflict() {
  MERGE_STATUS=$(git status | grep -i "unmerged paths")
  if [ -n "${MERGE_STATUS}" ]
  then
    echo "Resolve merge conflict before finishing the hotfix"
    exit 2
  fi
}

createHotfix() {
  read -rp "Name of your hotfix: " HOTFIX_NAME
  echo "Creating hotfix ${HOTFIX_NAME}"
  # Init hotfix branch
  git checkout -b hotfix/"${HOTFIX_NAME}"
  git push --tags -u origin hotfix/"${HOTFIX_NAME}"
}

rebaseBranch() {
  git checkout hotfix/"${HOTFIX_NAME}"
  git fetch "${1}"
  git rebase origin/"${1}"
  checkMergeConflict
  git push -f
  git checkout "${1}"
  git merge hotfix/"${HOTFIX_NAME}"
  checkMergeConflict
}

finishHotfix() {
  read -rp "Name of the hotfix you want to finish: " HOTFIX_NAME
  HOTFIX_COUNT=$(git ls-remote --heads origin hotfix/"${HOTFIX_NAME}" | wc -l)
  if [ "${HOTFIX_COUNT}" -lt 1 ]
  then
    echo "There is not existing hotfix with this name..."
    exit 2
  fi

  echo "Finishing hotfix ${HOTFIX_NAME}"

  rebaseBranch master
  rebaseBranch dev

  echo "test"

  # DELETE HOTFIX BRANCH
  git push origin --delete hotfix/"${HOTFIX_NAME}"
  git branch -D hotfix/"${HOTFIX_NAME}"

  incrementPatchVersion master
  incrementPatchVersion dev

  # CREATE AND PUSH TAG
  git checkout master
  git tag -a "${PACKAGE_VERSION}" -m "Tag ${PACKAGE_VERSION}"
  git push --follow-tags
}

publishHotfix() {
  echo "Publishing a new hotfix..."
  . ./config
  STATUS_CODE=$(curl -X POST --write-out %{http_code} --silent --output /dev/null \
  https://api.github.com/repos/"${GIT_REPOS_OWNER}"/"${GIT_REPOS_NAME}"/releases \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: Bearer ${GITHUB_PERSONAL_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"tag_name\": \"${PACKAGE_VERSION}\",
    \"target_commitish\": \"master\",
    \"name\": \"${PACKAGE_VERSION}\",
    \"body\": \"Hotfix ${HOTFIX_NAME}\",
    \"draft\": false,
    \"prerelease\": false
  }")

  if [ "$STATUS_CODE" -eq 201 ]
  then
    echo "The hotfix ${HOTFIX_NAME} has been published on version ${PACKAGE_VERSION}"
    exit 1
  else
    echo "An error occured when publishing the hotfix."
    echo "STATUS CODE: ${STATUS_CODE}"
    exit 2
  fi
}

if [ $# -eq 0 ]
then
  usage
  exit 1
fi

# Checking out master branch
git checkout master
git fetch
checkUnstagedChanges

if [ "$1" = "start" ]
then
  git pull --rebase
  createHotfix
elif [ "$1" = "finish" ]
then
  finishHotfix
  publishHotfix
fi
