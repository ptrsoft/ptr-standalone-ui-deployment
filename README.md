# webui-deployment
Automated secure static web UI deployment
## To test certificate stack 
###  first build the  test template
aws --region us-east-1 cloudformation package \
    --template-file templates/acm-certificate-test.yaml \
    --s3-bucket cf-static-secure-site \
    --output-template-file packaged.template

### verify , deploy and test
aws cloudformation validate-template --template-body file://packaged.template

aws --region us-east-1 cloudformation deploy \
    --stack-name certificate-test \
    --template-file  packaged.template \
    --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
    --parameter-overrides  DomainName=synectiks.net SubDomain=appkubesim CreateApex=no HostedZoneId=ZY8RNBR15YWYU \
    AppkubeDepartment=ops AppkubeProduct=appkube AppkubeEnvironment=prod AppkubeService=ui

## To test custom resource stack 
###  first build the  test template
aws --region us-east-1 cloudformation package \
    --template-file templates/custom-resource-test.yaml \
    --s3-bucket cf-static-secure-site \
    --output-template-file packaged.template
### verify , deploy and test
aws cloudformation validate-template --template-body file://packaged.template

aws --region us-east-1 cloudformation deploy \
    --stack-name custom-resource-test \
    --template-file  packaged.template \
    --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
    --parameter-overrides  AppkubeDepartment=ops AppkubeProduct=appkube \
    AppkubeEnvironment=sim AppkubeService=ui
Note:- make sure that parameters are in lower case , otherwise bucket name is not accepted as uppercase.

## To test cloudfront stack 
This stack is highly dependent on certificate and custom resource stack , so its difficult to test it independently, so ignoring this stack test. The main test should suffice.


## How to do the complete stack test

###  first build the  Main template
aws --region us-east-1 cloudformation package \
    --template-file main.yaml \
    --s3-bucket cf-static-secure-site \
    --output-template-file packaged.template
### verify , deploy and test
aws cloudformation validate-template --template-body file://packaged.template

aws --region us-east-1 cloudformation deploy \
    --stack-name ops-appkube-sim-ui \
    --template-file  packaged.template \
    --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
    --parameter-overrides  DomainName=synectiks.net SubDomain=appkubesim CreateApex=no HostedZoneId=ZY8RNBR15YWYU \
    AppkubeDepartment=ops AppkubeProduct=appkube AppkubeEnvironment=sim AppkubeService=ui

Note:- make sure that parameters are in lower case , otherwise bucket name is not accepted as uppercase. Also when u build the template , if u are not using S3 target location , template will not work.