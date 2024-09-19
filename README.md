
<!-- TOC -->
- [Introduction](#introduction)
- [What it does?](#what-it-does)
- [Architecture](#architecture)
- [How to use it](#how-to-use-it)
- [How to use it in tekton pipeline](#how-to-use-it-in-tekton-pipeline)
- [How to debug](#how-to-debug)
    - [To test certificate stack](#to-test-certificate-stack)
        - [first build the  test template](#first-build-the--test-template)
        - [verify , deploy and test](#verify--deploy-and-test)
    - [To test custom resource stack](#to-test-custom-resource-stack)
        - [first build the  test template](#first-build-the--test-template)
        - [verify , deploy and test](#verify--deploy-and-test)
    - [To test cloudfront stack](#to-test-cloudfront-stack)
    - [To test the route53 stack](#to-test-the-route53-stack)
        - [first build the  test template](#first-build-the--test-template)
        - [verify , deploy and test](#verify--deploy-and-test)
    - [How to do the complete stack test](#how-to-do-the-complete-stack-test)
        - [first build the  Main template](#first-build-the--main-template)
        - [verify , deploy and test](#verify--deploy-and-test)

<!-- /TOC -->
# Introduction 

Use this automated solution to deploy any full fledge front end(static site / SPA / PWA complete Website etc) in AWS. In the solution we just specify a config file with all data pertaining to the Organization / Department /  Account (Landing Zone) ... etc and it will create the entire stack with AWS cloudformation.We use Tekton as our CI/CD platform , so I also write some tekton jobs so that the sites can be deployed via tekton. The automation script take care of self discovery of the stack after deployment and we can query the AWS cloudformation stack and get every metadata about the stack you create and you could use that data for any stack that act as a cloud control plane.

# What it does?

-   It create secure S3 storage & all rules etc for hosting
-   The Build Website content is pushed to S3
-   The Secure certificate etc is created for the Site
-   Then it creates the CDN layer with the certificate.
-   It applies CloudFront Response Header Policies to add security headers to every server response
-   Then it update the CDN endpoint with route 53 domain for public access
-   Then it can create a soft waf layer to protect the site.

# Architecture 

![alt text](image.png)

# How to use it

./depoly.sh -c config.yaml.

For example , for ptr website deployment , we added ptr-website-config.yaml.
To deploy the ptr-website , all u need to do is

./depoly.sh -c ptr-website-config.yaml.

Note: We assume that you will configure the proper AWS context( either through role arn or access key / secret keys) before running the deploy.sh script.

# How to use it in tekton pipeline 

To deploy the UI repeatedly in tekton , please use the following tasks.

https://raw.githubusercontent.com/ptrsoft/ptr-tekton-automation/refs/heads/main/tasks/ptr-standalone-ui.yaml

For different Application UI deployment i Have writted few build pipelines as follows:

https://raw.githubusercontent.com/ptrsoft/ptr-tekton-automation/refs/heads/main/pipelines/ecom-b2c-sui-deployment.yaml

    This pipeline will do the following steps:
      - Using the git-clone catalog Task to clone the UI source Code
      - It will do build the UI code , and create the deployment artifacts that need to be copied to S3
      when "cleanup-cloudformation" parameter is true
      - Then it will git clone the deployment source code 
      - It will then invoke the cloud formation template using aws cli
    when "cleanup-cloudformation" parameter is false
      - sync UI code to s3 bucket
      - deploy all the nested stacks
      - Run cloudfront invalidation


# How to debug

There are few nested stacks that runs and build the entire solution - AWS cloudformation output may not be absolutely clear what breaks the stack. Also each of layer takes much time to build / deploy etc , so while developing , it makes some sense to build and tests individual stacks and then run the entire stack. Here follows the instruction to build and run individual stack

## To test certificate stack 
###  first build the  test template

aws --region us-east-1 cloudformation package \
    --template-file templates/acm-certificate-test.yaml \
    --s3-bucket cf-static-secure-site-promodeagro \

### verify , deploy and test

aws cloudformation validate-template --template-body file://packaged.template

aws --region us-east-1 cloudformation deploy \
    --stack-name certificate-test \
    --template-file  packaged.template \
    --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
    --parameter-overrides  DomainName=promodeagro.com.com SubDomain="" CreateApex=yes \
    HostedZoneId=Z00062013820EO6BYULDB \
    AppkubeDepartment=promodeagro AppkubeProduct=website AppkubeEnvironment=prod AppkubeService=ui

## To test custom resource stack 

###  first build the  test template
aws --region us-east-1 cloudformation package \
    --template-file templates/custom-resource-test.yaml \
    --s3-bucket cf-static-secure-site-ptr \
    --output-template-file packaged.template
### verify , deploy and test
aws cloudformation validate-template --template-body file://packaged.template

aws --region us-east-1 cloudformation deploy \
    --stack-name custom-resource-test \
    --template-file  packaged.template \
    --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
    --parameter-overrides  AppkubeDepartment=ops AppkubeProduct=ptrcloud \
    AppkubeEnvironment=prod AppkubeService=ui
Note:- make sure that parameters are in lower case , otherwise bucket name is not accepted as uppercase.

## To test cloudfront stack 
This stack is highly dependent on certificate and custom resource stack , so its difficult to test it independently, so ignoring this stack test. The main test should suffice.

## To test the route53 stack 

###  first build the  test template
aws --region us-east-1 cloudformation package \
    --template-file templates/route53-update-test.yaml \
    --s3-bucket cf-static-secure-site-ptr \
    --output-template-file packaged.template
### verify , deploy and test
aws cloudformation validate-template --template-body file://packaged.template

aws --region us-east-1 cloudformation deploy \
    --stack-name route53-update-test \
    --template-file  packaged.template \
    --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
    --parameter-overrides  AppkubeDepartment=ops AppkubeProduct=ptrcloud \
    AppkubeEnvironment=prod AppkubeService=ui \
    HostedZoneId=Z06401662L0WAGUZJFQOF CDNDomain="dlr31o9u647ea.cloudfront.net" DomainName=ptrtechnology.com SubDomain=ptrcloud

## How to do the complete stack test

###  first build the  Main template
aws --region us-east-1 cloudformation package \
    --template-file main.yaml \
    --s3-bucket cf-static-secure-site-ptr \
    --output-template-file packaged.template
### verify , deploy and test
aws cloudformation validate-template --template-body file://packaged.template

aws --region us-east-1 cloudformation deploy \
    --stack-name ops-appkube-ptrcloud-ui \
    --template-file  packaged.template \
    --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
    --parameter-overrides  DomainName=ptrtechnology.com SubDomain=ptrcloud CreateApex=no HostedZoneId=Z06401662L0WAGUZJFQOF \
    AppkubeDepartment=ops AppkubeProduct=ptrcloud AppkubeEnvironment=prod AppkubeService=ui \
    --disable-rollback

Note:- make sure that parameters are in lower case , otherwise bucket name is not accepted as uppercase. Also when u build the template , if u are not using S3 target location , template will not work.

