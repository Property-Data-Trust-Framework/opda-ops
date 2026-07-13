# Cheatsheet: AWS CLI

Paste-ready AWS CLI commands for the OPDA API family. All commands assume region
`eu-west-2` and AWS account `<AWS_ACCOUNT_ID>`. For procedures with context (deploy,
rotate, teardown) see the [[Runbook]]; for *why* things are shaped this way see
[[Decisions]].

> Substitute `<name>` per API, and `<AWS_ACCOUNT_ID>` with the real account ID.

## ECS (shared mTLS proxy — opda-ops/terraform/shared-proxy)

```bash
# Force-redeploy ECS service so the proxy reloads SSM-backed certs
aws ecs update-service --cluster opda-shared-proxy-dev-cluster --service opda-shared-proxy-dev-service --force-new-deployment --region eu-west-2

# List running tasks for an ECS service
aws ecs list-tasks --cluster opda-shared-proxy-dev-cluster --service-name opda-shared-proxy-dev-service --region eu-west-2

# Describe service: desired/running counts and last deployment status
aws ecs describe-services --cluster opda-shared-proxy-dev-cluster --services opda-shared-proxy-dev-service --region eu-west-2
```

## SSM — cert / credential rotation

> P1 escape hatch; values are overwritten on the next deploy unless the GitHub secret
> is also updated. Paths use `name_prefix` (`<name>-<env>`) post shared-VPC migration
> ([[ADR-0007-shared-vpc-ssm|ADR-0007]]).

```bash
# Transport cert (Raidiam-issued; outbound mTLS to introspection — server TLS is the Let's Encrypt cert per ADR-0004)
aws ssm put-parameter --name /opda-lr-facade-dev/transport_certificate --value file://keys/server.crt --type String --overwrite --region eu-west-2

# Transport key (encrypted at rest)
aws ssm put-parameter --name /opda-lr-facade-dev/transport_key --value file://keys/server.key --type SecureString --overwrite --region eu-west-2

# CA trusted list (verifies incoming client certs)
aws ssm put-parameter --name /opda-lr-facade-dev/ca_trusted_list --value file://keys/ca_trusted_list.pem --type String --overwrite --region eu-west-2

# Raidiam JWT signing key (private key only). Path uses name_prefix.
aws ssm put-parameter --name /opda-lr-facade-dev/signing_key --value file://certs/rtssigning.key --type SecureString --overwrite --region eu-west-2

# HMLR credentials (have ignore_changes=[value] in TF — safe to set out-of-band)
aws ssm put-parameter --name /opda-lr-facade-dev/hmlr/endpoint --value "https://bgtest.landregistry.gov.uk/b2b/BGStubService/OfficialCopyWithSummaryV2_1WebService" --type String --overwrite --region eu-west-2
aws ssm put-parameter --name /opda-lr-facade-dev/hmlr/username --value "<username>" --type SecureString --overwrite --region eu-west-2
aws ssm put-parameter --name /opda-lr-facade-dev/hmlr/password --value "<password>" --type SecureString --overwrite --region eu-west-2
aws ssm put-parameter --name /opda-lr-facade-dev/hmlr/client_certificate --value file://certs/hmlr-client.pem --type SecureString --overwrite --region eu-west-2
aws ssm put-parameter --name /opda-lr-facade-dev/hmlr/client_key --value file://certs/hmlr-client.key --type SecureString --overwrite --region eu-west-2

# OS Places API key (opda-os-api). Path uses name_prefix.
aws ssm put-parameter --name /opda-os-api-dev/os_api_key --value "<key>" --type SecureString --overwrite --region eu-west-2
```

```bash
# Read a parameter (no decryption — confirm presence + type)
aws ssm get-parameter --name /opda-lr-facade-dev/transport_certificate --region eu-west-2

# Read a SecureString with decryption (avoid on shared screens)
aws ssm get-parameter --name /opda-lr-facade-dev/transport_key --with-decryption --region eu-west-2

# List parameters by path prefix (one API)
aws ssm describe-parameters --parameter-filters "Key=Name,Option=BeginsWith,Values=/opda-lr-facade-dev/" --region eu-west-2

# Read shared-VPC outputs
aws ssm get-parameter --name /opda/shared/vpc_id --region eu-west-2
aws ssm get-parameter --name /opda/shared/private_subnet_ids --region eu-west-2
aws ssm get-parameter --name /opda/shared/public_subnet_ids --region eu-west-2
aws ssm get-parameter --name /opda/shared/vpc_endpoints_security_group_id --region eu-west-2
aws ssm get-parameter --name /opda/shared/execute_api_vpc_endpoint_id --region eu-west-2
```

## ELB — find NLB DNS (Bruno baseUrl / dev cert SAN)

```bash
# NLB DNS name (used as Bruno baseUrl when no custom domain is wired)
aws elbv2 describe-load-balancers --names opda-shared-proxy-dev --query "LoadBalancers[0].DNSName" --output text --region eu-west-2
```

## Lambda — sanity / debug

```bash
# Confirm a Lambda is pointing at the expected image SHA
aws lambda get-function --function-name opda-lr-facade-dev --query "Code.ImageUri" --output text --region eu-west-2
aws lambda get-function --function-name opda-lr-facade-dev-authorizer --query "Code.ImageUri" --output text --region eu-west-2

# Invoke for a quick health check (writes response to /tmp/out.json)
aws lambda invoke --function-name opda-lr-facade-dev --payload '{"requestContext":{"http":{"method":"GET"}},"rawPath":"/health"}' --cli-binary-format raw-in-base64-out /tmp/out.json --region eu-west-2
```

## DynamoDB (opda-mra-api)

```bash
# Describe coalfield table
aws dynamodb describe-table --table-name opda-mra-api-coalfields-dev --region eu-west-2

# Lookup one UPRN by partition key
aws dynamodb get-item --table-name opda-mra-api-coalfields-dev --key '{"uprn":{"S":"100012345678"}}' --region eu-west-2

# Item count (slow on large tables — prefer describe-table.ItemCount)
aws dynamodb scan --table-name opda-mra-api-coalfields-dev --select COUNT --region eu-west-2
```

## Logs

```bash
# Tail Lambda / ECS logs (requires AWS CLI v2 'logs tail')
aws logs tail /aws/lambda/opda-lr-facade-dev --follow --region eu-west-2
aws logs tail /aws/lambda/opda-lr-facade-dev-authorizer --follow --region eu-west-2
aws logs tail /ecs/opda-shared-proxy-dev --follow --region eu-west-2

# Filter logs for a FAPI interaction id (replace the UUID)
aws logs filter-log-events --log-group-name /aws/lambda/opda-lr-facade-dev --filter-pattern "11111111-2222-3333-4444-555555555555" --region eu-west-2
```

## Teardown follow-ups (manual, only when the destroy script isn't enough)

```bash
# Delete Terraform state file for an env (after teardown)
aws s3 rm s3://ops-terraform-state-<AWS_ACCOUNT_ID>/opda-os-api/dev/terraform.tfstate

# Delete a stray CloudWatch log group post-teardown
aws logs delete-log-group --log-group-name /aws/lambda/opda-os-api-dev --region eu-west-2
```

## Org Browser deploy (opda-ops/org-browser)

```bash
# Sync built static artifact to S3 (after `npm run build` produces dist/)
aws s3 sync opda-ops/org-browser/dist/ s3://opda-org-browser-<AWS_ACCOUNT_ID>/ --delete --region eu-west-2

# Invalidate CloudFront after deploy (replace DIST_ID)
aws cloudfront create-invalidation --distribution-id DIST_ID --paths "/*"

# Quick distribution health check
aws cloudfront list-distributions --query "DistributionList.Items[?Comment=='opda-org-browser'].{Id:Id,Status:Status,Enabled:Enabled,Domain:DomainName}" --output table
```

## API Docs deploy (opda-ops/api-docs)

```bash
# List all published API specs in S3 (check a spec landed after a deploy)
aws s3 ls s3://opda-api-docs-<AWS_ACCOUNT_ID>/specs/ --region eu-west-2

# Build + deploy the API docs site (idempotent)
./deploy-api-docs.sh

# Tear down (slow — CloudFront propagation takes 10-20 minutes)
./teardown-api-docs.sh

# Quick health check on the api-docs distribution
aws cloudfront list-distributions --query "DistributionList.Items[?Comment=='opda-api-docs'].{Id:Id,Status:Status,Enabled:Enabled,Domain:DomainName}" --output table
```

## Demo SPA — diagnose/fix stale CloudFront cache (opda-demo-bff)

```bash
# Resolve bucket + distribution from Terraform outputs
BUCKET=$(cd opda-demo-bff/terraform && terraform output -raw spa_bucket); CF_DOMAIN=$(cd opda-demo-bff/terraform && terraform output -raw cloudfront_domain); DIST_ID=$(aws cloudfront list-distributions --query "DistributionList.Items[?DomainName=='$CF_DOMAIN'].Id | [0]" --output text)

# >0 = new index.html IS in S3 (cache issue); 0 = redeploy needed
aws s3 cp "s3://$BUCKET/index.html" - | grep -c headlower
aws cloudfront create-invalidation --distribution-id "$DIST_ID" --paths "/demo" "/demo/" "/demo/*"
```

```bash
# Edge-vs-origin + cache-config diagnostics (run the BUCKET/DIST_ID block above first)
curl -s https://ext.smartpropdata.org.uk/demo/ | grep -c headlower   # EDGE (CloudFront): >0 new, 0 old
aws s3 cp "s3://$BUCKET/index.html" - | grep -c headlower            # ORIGIN (S3 truth): edge!=origin => cache is the cause
aws cloudfront get-distribution-config --id "$DIST_ID" --query 'DistributionConfig.{Root:DefaultRootObject,Behaviors:CacheBehaviors.Items[].PathPattern,DefaultTTL:DefaultCacheBehavior}'
aws s3api head-object --bucket "$BUCKET" --key index.html --query '{LastModified:LastModified,CacheControl:CacheControl,ContentType:ContentType}'
```
