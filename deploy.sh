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
organization=""
domain=""
subdomain=""
hostedzoneid=""
purehtmlcsspages=""
IsApexDomain=""

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
    AppkubeDepartment=$(yq eval '.apptags.department' $configfile)
    AppkubeProduct=$(yq eval '.apptags.product' $configfile)
    AppkubeEnvironment=$(yq eval '.apptags.environment' $configfile)
    AppkubeService=$(yq eval '.apptags.service' $configfile) 
    repo=$(yq eval '.git.repo' $configfile)
    git_tag=$(yq eval '.git.tag' $configfile)
    rebuildstack=$(yq eval '.general.rebuild-stack' $configfile)
    domain=$(yq eval '.general.domain' $configfile)
    subdomain=$(yq eval '.general.subdomain' $configfile)
    hostedzoneid=$(yq eval '.general.hostedzoneid' $configfile)
    onlyupdate=$(yq eval '.general.onlyupdate' $configfile)
    purehtmlcsspages=$(yq eval '.general.purestaticpages' $configfile)
    IsApexDomain=$(yq eval '.general.apexdomain' $configfile)
    organization=$(yq eval '.general.organization' $configfile)

else
    ## parse App app_tags
    AppkubeDepartment=$(echo "${app_tags}" | awk -F ':' '{print $1}')
    AppkubeProduct=$(echo "${app_tags}" | awk -F ':' '{print $2}')
    AppkubeEnvironment=$(echo "${app_tags}" | awk -F ':' '{print $3}')
    AppkubeService=$(echo "${app_tags}" | awk -F ':' '{print $4}')
fi

buildui() {
    echo "deleting existing checkout folder"
    clean-checkout-folder 2>/dev/null>&1
    echo "cloning the source to checkout folder"
    git clone "$1" checkout
    echo "Starting to build the source code"
    pushd checkout && npm install -f && npm run build && pushd +1
}

checkout() {
    echo "using configs from config file"
    echo "cleaning existing checkout folder"
    clean-checkout-folder 2>/dev/null>&1
    echo "cloning source to checkout folder"
    git clone "$1" checkout
}


clean-www-folder() {
    rm -rf www/* 
}
## copy the build outcome folder contents in www folder
copy-ui-build-in-www() {
    if ispurehtmlcsspages;then
        echo "copying root folder contents from checkout to www"
        cp -r checkout/* www/
    else
        echo "copying build folder contents from build to www"
        cp -r checkout/build/* www/
    fi
    cp -r error-pages/* www/
    echo "www folder contents after build"
    ls -a www/
}

## clean the checkout folder
clean-checkout-folder() {
    echo "deleting checkout folder"
    rm -rf checkout
}

check-existing-stack() {
    aws cloudformation list-stacks --no-paginate --output json --stack-status-filter "CREATE_COMPLETE" "UPDATE_COMPLETE" "ROLLBACK_COMPLETE" "ROLLBACK_FAILED" "DELETE_FAILED" --query 'StackSummaries[*].StackName' | grep $1 > /dev/null
    if [ $? -eq 0 ]; then
        true
    else
        false
    fi
}

# Function to clean the existing buckets , this deleteion is required to cleanly delete the stack

clean-existing-buckets() {
    echo "cleaning the root and log bucket of the stack"
    S3BucketRoot=$(aws cloudformation describe-stacks --stack-name "$1" --query 'Stacks[0].Outputs[?OutputKey==`S3BucketRoot`].OutputValue' --output text)
    S3BucketLogs=$(aws cloudformation describe-stacks --stack-name "$1" --query 'Stacks[0].Outputs[?OutputKey==`S3BucketLogs`].OutputValue' --output text)
    # aws s3 rm s3://"$S3BucketRoot" --recursive
    # aws s3 rm s3://"$S3BucketLogs" --recursive
    # aws s3api delete-bucket --bucket "$S3BucketRoot"
    # aws s3api delete-bucket --bucket "$S3BucketLogs"
    aws s3 rb s3://"$S3BucketRoot" --force
    aws s3 rb s3://"$S3BucketLogs" --force
}
# function to delete the existing stack if user requests so
delete-existing-stack-if-user-requests() {
        # existing=$(check-existing-stack $1)
        # echo "existing variable value : $existing "
        echo "entering existing stack delete section"
        if check-existing-stack "$1"; then
            echo "stack exist with the name: "$1""
            if rebuild-stack; then
                echo "deleting the stack"
                clean-existing-buckets "$1" 
                delete-stack "$1"
                keep-waiting-until-stack-deleted "$1"
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

isonlyupdate() {
  if [[ "$onlyupdate" == "true" ]]; then
    true
  else
    false
fi
}

ispurehtmlcsspages() {
  if [[ "$purehtmlcsspages" == "true" ]]; then
    true
  else
    false
fi
}

# Function to delete the stack
delete-stack() {
    aws cloudformation delete-stack --stack-name $1 --output text 2>/dev/null
    iferror "Delete Stack Api faile for some unknown reason"
}

# # Function to check the stack status
# check_stack_status() {
#     aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query 'Stacks[0].StackStatus' --output text 2>/dev/null
# }

# Function to check the stack status
check_stack_status() {
    aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query 'Stacks[0].StackStatus' --output text 
}

# Function that check delete status and wait upto creation
keep-waiting-until-stack-created(){
    # Polling interval in seconds
    INTERVAL=30
    echo "Waiting for CloudFormation stack '$1' to be created..."
    # Initial status check
    STATUS=$(check_stack_status)

    echo "Checking status for stack: $1"
    echo "Current status: $STATUS"

    # Loop until the stack reaches a completion status
    while [[ "$STATUS" != "CREATE_COMPLETE" && "$STATUS" != "UPDATE_COMPLETE" && "$STATUS" != "ROLLBACK_COMPLETE" && "$STATUS" != "UPDATE_ROLLBACK_COMPLETE" && "$STATUS" != "CREATE_FAILED" && "$STATUS" != "DELETE_COMPLETE" ]]; do
        echo "Stack is in $STATUS status. Waiting for $INTERVAL seconds..."
        sleep $INTERVAL
        STATUS=$(check_stack_status)
    done
    echo "Final stack status: $STATUS"
    # Check if stack creation or update was successful
    if [[ "$STATUS" == "CREATE_COMPLETE" || "$STATUS" == "UPDATE_COMPLETE" ]]; then
        echo "Stack operation was successful."
    else
        echo "Stack operation failed or was rolled back."
    fi
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
    --s3-bucket cf-static-secure-site-"$organization" \
    --output-template-file packaged.template >/dev/null 2>&1

    iferror "Building cloudformation package failed"
}

deploy-with-cloudformation-script() {
    aws cloudformation validate-template --template-body file://packaged.template >/dev/null 2>&1

    iferror "template validation failed"
 
    echo "starting the main cloudformation script deployment"
    
    aws --region us-east-1 cloudformation deploy \
        --stack-name "$1" \
        --template-file  packaged.template \
        --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
        --parameter-overrides  DomainName="$domain" SubDomain="$subdomain"  HostedZoneId="$hostedzoneid" \
        AppkubeDepartment="$AppkubeDepartment" AppkubeProduct="$AppkubeProduct" AppkubeEnvironment="$AppkubeEnvironment" \
        AppkubeService="$AppkubeService" CreateApex="$IsApexDomain"
}

updates3andrefreshcdn() {
    echo "Getting root bucket from the stack "$1""

    S3BucketRoot=$(aws cloudformation describe-stacks --stack-name "$1" \
    --query 'Stacks[0].Outputs[?OutputKey==`S3BucketRoot`].OutputValue' \
    --output text 2>/dev/null>&1)

    iferror "could not fetch root bucket"
    
    echo "Root bucket is : "$S3BucketRoot" "

    echo "Synching root bucket"

    aws s3 sync www s3://"$S3BucketRoot" --delete >/dev/null 2>&1
    
    iferror "could not sync root bucket"
    
    echo "Getting CloudFront Distribution Id"

    CFDistributionId=$(aws cloudformation describe-stacks --stack-name "$1" \
    --query 'Stacks[0].Outputs[?OutputKey==`CFDistributionId`].OutputValue' \
    --output text 2>/dev/null>&1)

    iferror "could not fetch cloud front ditribution id"

    echo "Got Cloudfront Distribution id : '$CFDistributionId' "

    echo "Doing cloudfront invalidatation"
    
    invalidation_output=$(aws cloudfront create-invalidation --distribution-id "$CFDistributionId" --paths "/*")

    # echo "invalidation output is: '$invalidation_output' "

    invalidation_id=$(echo "$invalidation_output" | grep -oP '(?<="Id": ")[^"]*' | cut -d'"' -f1)

    echo "invalidation id  is '$invalidation_id' "

    echo "Waiting for invalidatation"      
    aws cloudfront wait invalidation-completed --distribution-id "$CFDistributionId" --id "$invalidation_id" --debug true >/dev/null 2>&1
    echo "Invalidation completed, Invalidation ID: $invalidation_id"
}
updatecmdb() {
    aws cloudformation describe-stacks --stack-name "$1" --query 'Stacks[0].Outputs[].[OutputKey,OutputValue]' --output json > output.json
    aws cloudformation describe-stacks --stack-name "$1" --query 'Stacks[0].Outputs[].[OutputKey,OutputValue]' --output table 
}

iferror() {
    if [ $? -ne 0 ]; then
        echo "$1"
        exit 1
    fi
}

echo "configfile: $configfile"
echo "repo getting deployed: $repo"
echo "git tag : $git_tag"
echo "AppkubeDepartment Value: $AppkubeDepartment"
echo "AppkubeProduct Value: $AppkubeProduct"
echo "AppkubeEnvironment Value: $AppkubeEnvironment"
echo "AppkubeService Value: $AppkubeService"
echo "Create Apex Domain Value: $IsApexDomain"
echo "Remaining arguments: $@"

STACK_NAME="$AppkubeDepartment-$AppkubeProduct-$AppkubeEnvironment-$AppkubeService"
echo "stack name formed is : $STACK_NAME "
## cleaning stack beforehand if requested by user , because UI build takes more time and user simply complete UI build and then fail
delete-existing-stack-if-user-requests "$STACK_NAME"

if  isonlyupdate; then 
    echo "doing onlyupdate"
    if ! (ispurehtmlcsspages);then
        buildui "$repo"
    else 
        checkout "$repo"
    fi
    clean-www-folder
    copy-ui-build-in-www
    clean-checkout-folder
    updates3andrefreshcdn "$STACK_NAME"
else 
    if ! (ispurehtmlcsspages);then
        echo "doing complete ui build"
        buildui "$repo"
    else 
        echo "doing only checkout of repo"
        checkout "$repo"
    fi
    clean-www-folder
    copy-ui-build-in-www
    clean-checkout-folder
    build-cloudformation-script-package
    deploy-with-cloudformation-script "$STACK_NAME"
    ## sometime CF script dont copt the www contents , so added extra steps
    keep-waiting-until-stack-created "$STACK_NAME"
    updates3andrefreshcdn "$STACK_NAME"
fi
updatecmdb "$STACK_NAME"



