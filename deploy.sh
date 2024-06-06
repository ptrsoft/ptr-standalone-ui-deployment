#!/usr/bin/env bash

# ./build.sh [component] [tag] [-r registry] [-u username] [-p password]
# leave registry empty if default registry [docker.io] used
# Parse options using getopt

TEMP=$(getopt -o r:t:a: --long repo:,tag:,apptags: -n 'deploy.sh' -- "$@")
if [ $? != 0 ]; then
    echo "Terminating..." >&2
    exit 1
fi

# Note the quotes around `$TEMP`: they are essential!
eval set -- "$TEMP"

# Initialize default values

AppkubeDepartment=""
AppkubeProduct=""
AppkubeEnvironment=""
AppkubeService=""
repo=""
git_tag=""
app_tags=""


while true; do
    case "$1" in
        -r | --repo )
           repo=$2; shift 2;;
        -t | --tag )
           git_tag=$2; shift 2;;
        -a | --apptags )
           app_tags=$2; shift 2;;
        -- )
            shift; break ;;
        * )
            break ;;
    esac
done

## parse App app_tags
AppkubeDepartment=$(echo "${app_tags}" | awk -F ':' '{print $1}')
AppkubeProduct=$(echo "${app_tags}" | awk -F ':' '{print $2}')
AppkubeEnvironment=$(echo "${app_tags}" | awk -F ':' '{print $3}')
AppkubeService=$(echo "${app_tags}" | awk -F ':' '{print $4}')

echo "repo getting deployed: $repo"
echo "git tag : $git_tag"
echo "AppkubeDepartment Value: $AppkubeDepartment"
echo "AppkubeProduct Value: $AppkubeProduct"
echo "AppkubeEnvironment Value: $AppkubeEnvironment"
echo "AppkubeService Value: $AppkubeService"
echo "Remaining arguments: $@"