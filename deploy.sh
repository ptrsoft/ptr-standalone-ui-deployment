#!/usr/bin/env bash

# ./deploy.sh  [-r gitrepo] [-t tag] [-a app_tags]
# app_tags format is dept:product:env:service like ops:ptrwebsite:prod:websiteui
# ./deploy.sh [-c config.yaml] --it takes all info from config file
# leave tag empty if you want to use latest

# Ensure the AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "AWS CLI not found. Please install it to proceed."
    exit 1
fi

# Ensure the yq is installed
if ! command -v yq &> /dev/null; then
    echo "yq command not found. Please install it to proceed."
    exit 1
fi

# Check for required arguments
if [ $# -le 1 ]; then
    echo "Usage:./deploy.sh [-c config.yaml] --it takes all info from config file"
    echo "Usage:./deploy.sh  [-r gitrepo] [-t tag] [-a app_tags]"
    exit 1
fi

# Parse options using getopt

TEMP=$(getopt -o c:r:t:a: --long config:,repo:,tag:,apptags: -n 'deploy.sh' -- "$@")
if [ $? != 0 ]; then
    echo "Terminating..." >&2
    exit 1
fi

# Note the quotes around `$TEMP`: they are essential!
eval set -- "$TEMP"


# Initialize default values
configfile=""
AppkubeDepartment=""
AppkubeProduct=""
AppkubeEnvironment=""
AppkubeService=""
repo=""
git_tag=""
app_tags=""
rebuildstack=""
domain=""
subdomain=""
hostedzoneid=""
## parse the arguments 
while true; do
    case "$1" in
        -c | --config )
            configfile=$2; shift 2; break;;
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


if [ -n $configfile ]; then
    echo "using configs from config file"
  # Read the YAML file using yq
    AppkubeDepartment=$(yq eval '.apptags.department' config.yaml)
    AppkubeProduct=$(yq eval '.apptags.product' config.yaml)
    AppkubeEnvironment=$(yq eval '.apptags.environment' config.yaml)
    AppkubeService=$(yq eval '.apptags.service' config.yaml) 
    repo=$(yq eval '.git.repo' config.yaml)
    git_tag=$(yq eval '.git.tag' config.yaml)
    rebuildstack=$(yq eval '.general.rebuild-stack' config.yaml)
    domain=$(yq eval '.general.domain' config.yaml)
    subdomain=$(yq eval '.general.subdomain' config.yaml)
    hostedzoneid=$(yq eval '.general.hostedzoneid' config.yaml)
else
    ## parse App app_tags
    AppkubeDepartment=$(echo "${app_tags}" | awk -F ':' '{print $1}')
    AppkubeProduct=$(echo "${app_tags}" | awk -F ':' '{print $2}')
    AppkubeEnvironment=$(echo "${app_tags}" | awk -F ':' '{print $3}')
    AppkubeService=$(echo "${app_tags}" | awk -F ':' '{print $4}')
fi

buildui() {
    echo "using configs from config file"
    git clone $1 checkout
    pushd checkout && npm install && npm run build && pushd +1
}

clean-www-folder() {
    pushd www && rm -rv !("403.html"|"404.html") && pushd +1
}
## copy the build folder contents in www folder
copy-ui-build-in-www() {
    echo "copying build folder contents from build to www"
    cp -r checkout/build/* www/
    echo "www folder contents after build"
    ls -a www/
}

## clean the checkout folder
clean-checkout-folder() {
    echo "deleting checkout folder"
    rm -rf checkout
}

check-existing-stack() {
    aws cloudformation list-stacks --no-paginate --output json --stack-status-filter "CREATE_COMPLETE" "UPDATE_COMPLETE"   --query 'StackSummaries[*].StackName' | grep $1 > /dev/null
    if [ $? -eq 0 ]; then
        true
    else
        false
    fi
}

# Function to clean the existing buckets , this deleteion is required to cleanly delete the stack

clean-existing-buckets() {
    echo "cleaning the root and log bucket of the stack"
    S3BucketRoot=$(aws cloudformation describe-stacks --stack-name $1 --query 'Stacks[0].Outputs[?OutputKey==`S3BucketRoot`].OutputValue' --output text)
    S3BucketLogs=$(aws cloudformation describe-stacks --stack-name $1 --query 'Stacks[0].Outputs[?OutputKey==`S3BucketLogs`].OutputValue' --output text)
    aws s3 rm s3://$S3BucketRoot --recursive
    aws s3 rm s3://$S3BucketLogs --recursive
    aws s3api delete-bucket --bucket $S3BucketRoot
    aws s3api delete-bucket --bucket $S3BucketLogs
}
# function to delete the existing stack if user requests so
delete-existing-stack-if-user-requests() {
        # existing=$(check-existing-stack $1)
        # echo "existing variable value : $existing "
        if check-existing-stack $1; then
            echo "stack exist with the name"
            if rebuild-stack; then
                echo "deleting the stack"
                clean-existing-buckets $1 
                delete-stack $1
                keep-waiting-until-stack-deleted $1
            fi
        else
            echo "stack does not exist with the name: $1"
        fi
}

rebuild-stack() {
  if [[ "$rebuildstack" == "true" ]]; then
    true
  else
    false
fi
}

# Function to delete the stack
delete-stack() {
    aws cloudformation delete-stack --stack-name $1 --output text 2>/dev/null
    if [ $? -ne 0 ]; then
        # If describe-stacks fails, it likely means the stack has been deleted
        echo "Delete Stack Api faile for some unknown reason"
    fi
}

# Function to check the stack status
check_stack_status() {
    aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query 'Stacks[0].StackStatus' --output text 2>/dev/null
}
# Function that check delete status and wait upto deletion
keep-waiting-until-stack-deleted(){
    echo "Waiting for CloudFormation stack '$1' to be deleted..."
    # Loop until the stack is deleted
    while true; do
        STATUS=$(check_stack_status)

        if [ $? -ne 0 ]; then
            # If describe-stacks fails, it likely means the stack has been deleted
            echo "CloudFormation stack '$1' has been successfully deleted."
            break
        elif [ "$STATUS" == "DELETE_FAILED" ]; then
            echo "CloudFormation stack deletion failed. Please check the AWS CloudFormation console for more details."
            exit 1
        else
            echo "Stack status: $STATUS. Waiting for deletion to complete..."
        fi
        # Wait for a while before checking again
        sleep 10
    done
}
build-cloudformation-script-package() {
    aws --region us-east-1 cloudformation package \
    --template-file main.yaml \
    --s3-bucket cf-static-secure-site-ptr \
    --output-template-file packaged.template
}

deploy-with-cloudformation-script() {
    aws cloudformation validate-template --template-body file://packaged.template
    if [ $? -ne 0 ]; then
        echo "template validation failed"
        exit 1
    fi
    echo "starting the main cloudformation script deployment"

    aws --region us-east-1 cloudformation deploy \
        --stack-name ops-appkube-ptrcloud-ui \
        --template-file  packaged.template \
        --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
        --parameter-overrides  DomainName="$domain" SubDomain="$subdomain"  HostedZoneId="$hostedzoneid" \
        AppkubeDepartment=$AppkubeDepartment AppkubeProduct=$AppkubeProduct AppkubeEnvironment=$AppkubeEnvironment AppkubeService=$AppkubeService 
}

echo "configfile: $configfile"
echo "repo getting deployed: $repo"
echo "git tag : $git_tag"
echo "AppkubeDepartment Value: $AppkubeDepartment"
echo "AppkubeProduct Value: $AppkubeProduct"
echo "AppkubeEnvironment Value: $AppkubeEnvironment"
echo "AppkubeService Value: $AppkubeService"
echo "Remaining arguments: $@"

STACK_NAME="$AppkubeDepartment-$AppkubeProduct-$AppkubeEnvironment-$AppkubeService"
echo "stack name formed is : $STACK_NAME "
# delete-existing-stack-if-user-requests $STACK_NAME
# buildui $repo
clean-www-folder
copy-ui-build-in-www
clean-checkout-folder
build-cloudformation-script-package
deploy-with-cloudformation-script STACK_NAME



