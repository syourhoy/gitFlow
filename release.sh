#!/bin/sh

usage() {
  echo "usage: ./release.sh [start / finish]"
  echo "start => Init a new release"
  echo "finish => Merge the release to master and dev and delete the branch"
}

getPackageVersion() {
  PACKAGE_VERSION=$(cat ../package.json \
  | grep version \
  | head -1 \
  | awk -F: '{ print $2 }' \
  | sed 's/[",]//g' \
  | xargs)
}

checkIfReleaseExist() {
  getPackageVersion
  RELEASE_COUNT=$(git ls-remote --heads origin release/"${PACKAGE_VERSION}" | wc -l)
  if [ "$RELEASE_COUNT" -ge 1 ]
  then
    echo "Release ${PACKAGE_VERSION} already exists"
    echo "Finish the current release before starting a new one"
    git checkout -- ../package.json
    exit 2
  fi
}

checkUnstagedChanges() {
  echo "Checking unstaged changes..."
  git diff-index --quiet HEAD --
  if [ $? -ge 1 ]
  then
    echo "There is some unstaged changes..."
    echo "Please, commit your changes before creating a new release."
    exit 2
  fi
}

checkMergeConflict() {
  MERGE_STATUS=$(git status | grep "unmerged paths")
  if [ -n "${MERGE_STATUS}" ]
  then
    echo "Resolve merge conflict before finishing the hotfix"
    exit 2
  fi
}

createRelease() {
  getPackageVersion
  git add ../package.json
  git commit -m "Init release ${PACKAGE_VERSION}" -- ../package.json
  git push
  echo "Creating release version ${PACKAGE_VERSION}"
  git flow release start "${PACKAGE_VERSION}"
  git push --tags -u origin release/"${PACKAGE_VERSION}"
}

finishRelease() {
  getPackageVersion
  echo "Finishing release version ${PACKAGE_VERSION}"
  git flow release finish "${PACKAGE_VERSION}"
  checkMergeConflict
  git checkout dev
  git push
  git checkout master
  git push --follow-tags
  git checkout dev
}

publishRelease() {
  echo "Publishing a new release..."
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
    \"body\": \"Release de la version ${PACKAGE_VERSION}\",
    \"draft\": false,
    \"prerelease\": false
  }")

  if [ "$STATUS_CODE" -eq 201 ]
  then
    echo "The release ${PACKAGE_VERSION} has been published!"
    exit 1
  else
    echo "An error occured when publishing the release."
    echo "STATUS CODE: ${STATUS_CODE}"
    exit 2
  fi
}

if [ $# -eq 0 ]
then
  usage
  exit 1
fi

# Checking out development branch
git checkout dev
git fetch
checkUnstagedChanges
git pull --rebase

if [ "$1" = "start" ]
then
  checkIfReleaseExist
  npm version minor --no-git-tag-version
  createRelease
elif [ "$1" = "finish" ]
then
  finishRelease
  publishRelease
fi
