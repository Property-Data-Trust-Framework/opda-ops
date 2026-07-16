# Key Learnings

The non-obvious things that bit us, so they don't bite again — organised by area, not
chronology. For the timeline see the [[Runbook]] milestones.

> **Decisions live in [[Decisions]] (ADRs); this page is the gotchas.** Where a section
> below records *why* something is built a certain way, it now points to the relevant
> ADR and keeps only the practical traps. The go-live gap register moved to
> [[Production-Readiness]].

Distilled from the project's working notes and deployment history (covering work to 2026-04-25).

---

## System architecture

The architecture and its evolution (per-API stacks → shared NLB/proxy → ALB-native
mTLS) is recorded in the ADRs: [[ADR-0001-per-api-self-contained-stacks|ADR-0001]],
[[ADR-0002-shared-nlb-path-routing-proxy|ADR-0002]],
[[ADR-0003-alb-native-mtls-regional-apigw|ADR-0003]]. Cost went from ~$174/month per
environment (7 per-API stacks) to ~$44/month flat after consolidation. What stays here
is the practical reference for *adding* an API.

### Architecture mapping (when adding the next .NET API)

| Layer | Go (`opda-lr-facade`) | .NET (`opda-uprn-validator`, etc.) |
|---|---|---|
| Lambda hosting | `httpadapter.New(router)` (algnhsa) | `AddAWSLambdaHosting(LambdaEventSource.RestApi)` |
| HTTP routing | manual `http.HandleFunc` | `[ApiController]` + `[HttpPost]`, or Minimal API |
| Middleware | `func(next http.Handler) http.Handler` chain | `IMiddleware` registered via `app.UseMiddleware<T>()` |
| Config + SSM | manual `os.Getenv` + SSM SDK | `Amazon.Extensions.Configuration.SystemsManager` SSM provider, `IOptions<T>` |
| Domain model | structs with `json:"..."` tags | C# records with `[JsonPropertyName("...")]` (`System.Text.Json`) |
| SOAP client (if needed) | hand-rolled XML + raw `HttpClient` | `dotnet-svcutil` against the WSDL — generates a typed client targeting the cross-platform `System.ServiceModel.*` packages. Falls back to hand-rolled `HttpClient` + `XmlSerializer` if the WSDL is awkward. |
| mTLS outbound | `tls.Config` with `Certificates` on `http.Client` | `HttpClientHandler.ClientCertificates.Add(cert)` |

Pipeline skeleton for new .NET APIs: `opda-ops/templates/dotnet/deploy.yml` — same ECR bootstrap → Terraform apply pattern as Go. WCF **server** is Windows-only and was never ported; **client** lives on as community-maintained `System.ServiceModel.*` packages and runs fine on Lambda's Amazon Linux. None of the current three .NET APIs need SOAP — flagged here only because a future facade-style API might.

### .NET Lambda packaging pitfalls

> Packaging *decision* (why `provided:al2023` self-contained): [[ADR-0009-container-lambda-packaging|ADR-0009]]. The traps below are what bit us on the way there.

The .NET Lambdas all run as containers off `provided:al2023` with self-contained single-file publish. The path to "working" was non-obvious — every base-image option except this one fails in a different way.

| Pitfall | Why it bites | Fix |
|---|---|---|
| `FROM public.ecr.aws/lambda/dotnet:9` with class-based handler | `AddAWSLambdaHosting` is a self-bootstrapping runtime, not a class handler — the dotnet base image's entrypoint hunts for a class handler and fails with `Unable to load type APIGatewayProxyFunction` | Use `provided:al2023` + self-contained single-file publish |
| `provided:al2023` default ENTRYPOINT | Its `/lambda-entrypoint.sh` validates a handler argument before calling bootstrap — refuses to start without one | Override `ENTRYPOINT ["/var/task/bootstrap"]` in the Dockerfile |
| `dotnet publish --no-restore` errors on RID | Restore ran without `-r linux-x64`; publish with `--self-contained` requires the same RID at restore time | Add `-r linux-x64` to `dotnet restore` as well as `dotnet publish` |
| `libicu` missing crash at cold start | `provided:al2023` has no ICU library; .NET self-contained publish requires ICU by default | `-p:InvariantGlobalization=true` on publish |
| Em dash `—` in SG description | AWS only accepts ASCII for security group descriptions | Use hyphen `-` in `terraform/lambda.tf` |
| `OpdaScopeFilter` always 401 on Lambda but works locally | `AddAWSLambdaHosting` marshals authorizer context into `HttpContext.User` claims — **not** `HttpContext.Items["LambdaRequestObject"]`. The `Items` key only applies to the non-hosting `AspNetCoreServer` package | Use `ScopesFromClaims` (`http.User.FindFirst("scope")`) — never `ScopesFromAuthorizer` (Items lookup) |
| `BYPASS_AUTH=true` behaviour depends on the deployed authorizer image | The current authorizer skips introspection/cert-binding on bypass but **injects a hard-coded `scope=land-registry`** into the context (`authorizer/main.go` `handleRequest`), so `land-registry`-gated endpoints pass; anything requiring a different scope still fails. Authorizers are image-pinned (`AUTHORIZER_IMAGE_TAG`) — an image predating the scope injection leaves `HttpContext.User` claimless and 401s every scope-gated route. | Default `BYPASS_AUTH=false`. Only flip to `true` for very early bootstrap (before Raidiam certs); document and put back. If bypass 401s, check the deployed authorizer image age first. |
| Provenance signer created but responses stay unsigned | `provenanceSigner` is a local variable in `Program.cs`. It does **not** need to be registered with DI — it is captured via closure in the route handler lambda. If you forget to update the route handler to use the closure, the signer is created at startup and then silently ignored. | In every route handler: `return provenanceSigner is not null ? Results.Ok(provenanceSigner.Sign(data)) : Results.Ok(data);` — see `opda-mra-api/src/OpdaMiningRemediation/Program.cs` as the canonical example. |

---

## Go Lambda packaging (`opda-lr-facade`, authorizer)

> Packaging *decision*: [[ADR-0009-container-lambda-packaging|ADR-0009]].

Both Go Lambdas run from `FROM scratch` with a binary named `bootstrap`. Two recurring traps:

| Pitfall | Why it bites | Fix |
|---|---|---|
| Authorizer `Runtime.InvalidEntrypoint` | Started with `FROM public.ecr.aws/lambda/provided:al2023` — base image's own ENTRYPOINT collided with `bootstrap`. Lambda was also configured `arm64` while Dockerfile built `amd64` | `FROM scratch`, binary named `bootstrap`, explicit `ENTRYPOINT ["/bootstrap"]`. Set `architectures = ["x86_64"]` on the Lambda |
| `x509: certificate signed by unknown authority` on every outbound HTTPS call | Scratch images have no CA bundle. Hidden during smoke test because `LOCAL_MOCK=true` + `BYPASS_AUTH=true` meant **no** outbound HTTPS happened. Manifested only when both flags came off | `COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt` in **both** Dockerfiles (facade + authorizer) |

.NET is not affected by the CA bundle issue — non-scratch base images already ship one.

---

## Raidiam OAuth (`private_key_jwt` with RS256)

> The *decisions* — `private_key_jwt` + RS256, and the cert-separation rule — are
> [[ADR-0005-private-key-jwt-rs256|ADR-0005]] and [[ADR-0004-public-ca-server-cert|ADR-0004]].
> Below is the runtime reference and the recurring traps.

### Discovery & portal reference

OpenID discovery doc lives at `/.well-known/openid-configuration` on the issuer. Production directory uses `https://matls-auth.directory.pdtf.raidiam.io`; sandbox uses `https://auth.sandbox.raidiam.io`.

| Field | Value |
|---|---|
| Token endpoint (mTLS) | `https://matls-auth.<host>/token` |
| Introspection endpoint (mTLS) | `https://matls-auth.<host>/token/introspection` |
| Token auth methods | `private_key_jwt`, `tls_client_auth` |
| Discovery-advertised signing alg | `PS256` — but Raidiam confirmed **RS256** is what they accept. Use RS256. |
| Cert-bound tokens | enabled (`tls_client_certificate_bound_access_tokens: true`) — `cnf.x5t#S256` claim binds the token to the client cert |

Portal credential mapping (when onboarding a new identity):

| Portal field | Where it goes at runtime |
|---|---|
| **Client ID** | `OAUTH_CLIENT_ID` GitHub secret → authorizer Lambda env var. Full URL form, e.g. `https://rp.directory.pdtf.raidiam.io/openid_relying_party/<uuid>` |
| **Application ID** | Raidiam internal — portal/support only, not used at runtime |
| **KID** | Key ID of the registered signing key. Belongs in the JWT `kid` header — but our authorizer omits `kid`, matching Raidiam's reference script |
| **mTLS cert subject** | `C=GB, O=OPDA Sandbox Trust Framework, OU=<org-id>, CN=<app-id>` |
| **mTLS cert issuer** | `Open Property Data Sandbox Issuing CA - G1` |
| **Fingerprints** | SHA-256 fingerprint = `x5t#S256` value embedded in cert-bound token `cnf` claim |

Onboarding files: `.key` → SSM `transport_key` and `private_key_jwt` signing; `.pem` (transport cert, OPDA-signed from CSR) → SSM `transport_certificate` and Bruno client cert; `.csr` → registration artifact only.

### Cert pairs and identities

Three completely separate cert/key pairs, distinct purposes, distinct SSM parameters. Confusing them costs hours. (Decision on which cert is used where: [[ADR-0004-public-ca-server-cert|ADR-0004]].)

| Cert pair | `keys/` path | Used for | GitHub secret | SSM parameter |
|---|---|---|---|---|
| `tls.*` | `keys/server/tls/tls.{crt,key}` | **Inbound server TLS** — cert the proxy presents to connecting clients. Must be from a publicly-trusted CA (Let's Encrypt etc.) when a custom domain is in use. Optional — omit for APIs without a domain (falls back to `rtstransport`). | `SERVER_TLS_CERTIFICATE` + `SERVER_TLS_KEY` | `server_tls_certificate` + `server_tls_key` |
| `rtstransport.*` | `keys/server/transport/transport.{crt,key}` | **Authorizer outbound mTLS** — presenting our Raidiam participant identity when calling the token/introspection endpoints. **Never** use as the server cert on externally-reachable endpoints. | `TRANSPORT_CERTIFICATE` + `TRANSPORT_KEY` | `transport_certificate` + `transport_key` |
| `rtssigning.*` | `keys/server/signing/signing.key` | **`private_key_jwt`** — signing the `client_assertion` JWT the authorizer sends with introspection requests | `SIGNING_KEY` | `signing_key` (SecureString, key only) |
| `dataprov.*` | `keys/server/provenance/dataprov.{key,pem}` | **Response provenance signing** — RSA signature over the JCS-canonicalised payload (see [ADR-0006](ADR-0006-provenance-rsa-sha256-jcs)) | `DATAPROV_KEY` | `dataprov_key` (SecureString) |

**Critical clarification (confirmed with Raidiam):** `rtstransport.*` is a **data consumer** cert — it identifies our code when calling Raidiam. It must **not** be used as the server cert on API endpoints. Callers validate the server cert hostname against the endpoint DNS name; a Raidiam-issued cert has no hostname SANs (its CN is a UUID participant identifier) and will fail standard TLS hostname validation. Use a cert from a widely-trusted public CA (Let's Encrypt, Entrust, DigiCert, AWS ACM) for the server-side TLS on any externally-reachable endpoint.

Two types of identity — keep them straight:

| Identity | Client ID | Used by | Unique per API? |
|---|---|---|---|
| **Provider (server)** | Set as GitHub secret `OAUTH_CLIENT_ID` — a unique URL per API registration in the Raidiam portal | The authorizer Lambda — authenticates to Raidiam to introspect tokens | **Yes** — each API has its own Raidiam application registration, its own client ID URL, and its own `rtssigning` key. Copying the signing key from another API would cause introspection failures. |
| **Consumer (client)** | Configured in Bruno via `prepare-bruno-env.sh` | Developer calling the API for testing (Bruno, `raidiam-script.sh`) | **No** — the consumer identity is shared; `keys/client/` can be copied from any existing API repo. |

JWT shape the authorizer builds on each call (no `kid` in header, RS256, jti UUID, exp now+300):

```
header   { "alg": "RS256", "typ": "JWT" }
payload  { "iss": "<client_id_url>", "sub": "<client_id_url>",
           "aud": "<introspection_endpoint>",
           "jti": "<uuid>", "iat": <now>, "exp": <now + 300s> }
```

Recurring traps:

| Pitfall | Root cause | Fix |
|---|---|---|
| `x509: certificate signed by unknown authority` on introspection | `CA_TRUSTED_LIST` still contained the dev self-signed CA from the smoke-test phase | Update GitHub secret to the contents of `raidiam/.../environments/opda-sandbox/ca_trusted_list.pem` |
| `tls: certificate required` on introspection | `TRANSPORT_CERTIFICATE` / `TRANSPORT_KEY` still contained dev self-signed certs | Replace with real `rtstransport.*` from Raidiam onboarding |
| `client_id: PLACEHOLDER` in JWT | `OAUTH_CLIENT_ID` GitHub secret never updated from placeholder | Set to full URL: `https://rp.directory.pdtf.raidiam.io/openid_relying_party/<uuid>` |
| Tokens expire mid-test | Raidiam access tokens are ~5 minutes | Re-run `raidiam-script.sh` whenever Bruno returns 401 |

---

## mTLS proxy / NLB (ECS Fargate)

> Enforcement *decision* (`VerifyClientCertIfGiven`, mTLS-at-edge): [[ADR-0011-security-model-mtls-oauth-introspection|ADR-0011]]. Server-cert separation: [[ADR-0004-public-ca-server-cert|ADR-0004]].

| Pitfall | Root cause | Fix |
|---|---|---|
| `no Tls-Certificate found on request` | Original proxy gated mTLS on SNI hostname (`matls-*` only). Raw NLB DNS name doesn't start with `matls-`, so the proxy never **requested** a client cert | Drop the SNI check; always request a client cert |
| New ECS tasks deactivating immediately after the SNI fix | Switched to `tls.RequireAndVerifyClientCert` — but NLB health checkers don't present a client cert, so health checks failed | Use `tls.VerifyClientCertIfGiven` — always requests, verifies if present, lets health checks through |
| Target group rename caused outage | Default Terraform behaviour deletes the old TG before creating a new one | Add `lifecycle { create_before_destroy = true }` to the TG. Required IAM additions: `elasticloadbalancing:ModifyListener` + `ModifyTargetGroup` |
| Cert rotation didn't take effect | Proxy reads SSM at container startup — Terraform doesn't cycle ECS tasks when only SSM **values** change | Force ECS deployment after SSM update (see [[Runbook]]) |
| `rtstransport` cert used as server cert caused hostname validation failures | Raidiam-issued transport certs have a UUID CN and no hostname SANs — presenting one as the server cert on a custom domain endpoint causes every standard TLS client to reject the handshake | Use a publicly-trusted cert (Let's Encrypt etc.) for server TLS; keep `rtstransport` exclusively for outbound Raidiam mTLS. Wire via `server_tls_certificate` / `server_tls_key` module vars |
| Server cert and transport cert share the same SSM path | When the mtls-proxy module only had one cert/key pair, the proxy used the transport cert for server TLS (wrong) and the authorizer also used it for outbound introspection (right). Splitting required separate SSM params and conditional env var logic | Module now has `server_tls_certificate` / `server_tls_key` optional vars. When set, the proxy uses these for inbound TLS; the authorizer always reads `transport_certificate` / `transport_key` for outbound Raidiam auth. The `outputs.tf` `ssm_transport_certificate_name` always returns the transport cert regardless — authorizer wiring is unaffected. |

---

## HMLR SOAP

| Pitfall | Notes |
|---|---|
| `messageId` must be numeric in HMLR test environment | XSD `Q1TextContentType` pattern allows alphanumeric, but the **test** endpoint silently rejects alphanumeric values with `"The Search criteria provided is invalid"`. Use a numeric value in dev/test. |
| `x509` failures on HMLR calls | `bgtest.landregistry.gov.uk` cert isn't in the standard Alpine CA bundle. Set `hmlr_insecure_skip_verify = true` in `deploy.yml` for non-prod. **Remove** when pointing at the production endpoint. |
| `ExternalReference` / `CustomerReference` | XSD says `minOccurs="1"` but our model has `*string` with `omitempty`. A caller omitting these will produce an invalid SOAP request. Open bug — tracked as a go-live fix. |
| Working test title | `GR506405` (City of Plymouth) — exercises every response field. |

---

## Bruno API client

Bruno is fiddly. Several silent-failure modes — none of them produce an error in the UI.

| Pitfall | Why it bites | Fix |
|---|---|---|
| `clientCertificate { ... }` block in `.bru` env file | Causes Bruno to **silently drop the entire environment on reload** — no error, just gone | `apply-bruno-env.sh` now handles cert configuration correctly; never write the block to the file manually |
| `clientCertificates` domain doesn't match URL hostname | Bruno only presents a client cert when the request hostname **exactly** matches a domain listed in `bruno.json` `clientCertificates`. If the domain was set while `outputs.tf` had a bug (`var.name` instead of `local.name_prefix`), it will be missing the `-dev` environment suffix — Bruno silently skips the cert, the proxy sets no `TLS-Certificate` header, and the authorizer returns 401 with `no Tls-Certificate found on request`. | Re-run `prepare-bruno-env.sh` after every deploy or outputs.tf change; or manually update `bruno.json` `clientCertificates[].domain` and `scripts/bruno.env` `CERT_DOMAIN` to match the actual endpoint hostname exactly. |
| Health check 200 ≠ client cert being sent | The proxy's `/health` route is handled by the proxy itself and returns 200 without forwarding to API Gateway or requiring a client cert. A 200 on health check only proves the proxy is alive and DNS resolves — it says nothing about whether Bruno presented its transport cert on the TLS handshake. | Use an authenticated endpoint to verify the full mTLS path; check CloudWatch authorizer logs for `no Tls-Certificate found on request`. |
| Cert not presented to a domain | Bruno only presents certs for domains explicitly listed in `bruno.json` `clientCertificates` | List **every** domain that needs a cert: both the API endpoint hostname and `matls-auth.directory.pdtf.raidiam.io`. |
| `apply-bruno-env.sh` fails on newer Bruno JSON format | Newer Bruno versions use `"clientCertificates": {"enabled": true, "certs": [...]}` instead of the old `"clientCertificates": [...]` array | `apply-bruno-env.sh` now handles both formats via a Python snippet that checks `isinstance(certs_field, dict)` |
| Auth header missing on a request | `auth:bearer` block in a request `.bru` file isn't honoured by the Bruno UI | Set bearer auth at **collection** level; set individual requests to `inherit` |
| Request becomes GET when it should be POST | Trailing slash in `baseUrl` + leading slash in path → `//path` → Go HTTP server returns 301 → Bruno follows the redirect as GET | Remove trailing slash from `baseUrl` in environments |
| Bootstrap script swallows args | `prepare-bruno-env.sh` originally took the environment as a positional `$1` — when called with the client ID URL first, the URL got swallowed as the env name | All copies now take `--environment` flag; never positional |
| `signingKey` persists between sessions | Confirmed: Bruno secret variables persist on this machine — only needs setting once per machine, not per session |

Operational requirement: Bruno **developer mode** does **not** persist between sessions — re-enable each time (Preferences → General → Enable Developer Mode).

---

## IAM

> Topology *decision* (per-repo role, OIDC, shared across envs): [[ADR-0010-github-oidc-aws-auth|ADR-0010]].

| Pitfall | Notes |
|---|---|
| GitHub Actions role policy changes don't take effect | Chicken-and-egg: the role needs the policy **before** CI can run with the new policy. Apply role-policy changes locally first. |
| `ecr:CreateRepository` / `ecr:DeleteRepository` missing | Easy to forget when scaffolding per-repo IAM — the deploy needs both. |
| Route53 IAM produces an invalid ARN | When no hosted zone is configured, the conditional ARN was being emitted as `arn:aws:route53:::hostedzone/` (empty). Conditionally include the statement only when a zone exists. |
| ELB IAM blocks TG `create_before_destroy` | Need `ModifyListener` + `ModifyTargetGroup` to swap a TG behind a listener without an outage. |
| SSM `PutParameter` AccessDenied on `signing_key` after shared-VPC migration | `ssm.tf` still used `/${var.name}/signing_key` but IAM policy was migrated to `parameter/${var.name}-*` (env-prefixed) | Use `/${local.name_prefix}/signing_key` everywhere |
| Custom domain: pipeline 403 on Route53 | `external_hosted_zone_id` must be added to `terraform/iam/terraform.tfvars` **before** applying IAM. The IAM role policy conditionally adds `route53:ChangeResourceRecordSets` on the hosted zone ARN. If you apply IAM without it, the pipeline cannot create the CNAME record. Fix: add the zone ID to `terraform.tfvars`, re-apply IAM locally (`terraform apply`), then re-run the pipeline. |
| `EXTERNAL_HOSTED_ZONE_ID` set as a variable, not a secret | This is a non-sensitive resource ID. In `deploy.yml` reference it as `${{ vars.EXTERNAL_HOSTED_ZONE_ID }}` not `${{ secrets.EXTERNAL_HOSTED_ZONE_ID }}`. Using `secrets` when it's a `var` silently passes an empty string. |

Per-repo IAM is in `terraform/iam/` with its own state file (`{repo}/iam/terraform.tfstate`). Effects:
- One GitHub Actions role per repo, **shared across environments**
- Role policy uses `${var.name}-*` wildcards to cover env-prefixed resources
- `terraform destroy` on an environment **does not** delete the role

After the shared-VPC migration the per-API IAM VPC block was trimmed: only SG management + describe + Lambda ENI lifecycle remain. The pipelines no longer need create/delete on VPC/NAT/subnet/IGW/endpoints.

---

## Terraform outputs — `mtls_endpoint`

The `outputs.tf` in every API repo exposes `mtls_endpoint` as the custom domain URL. An early version of the template used `var.name` (e.g. `opda-competition-api`) instead of `local.name_prefix` (e.g. `opda-competition-api-dev`), producing a URL missing the `-<env>` suffix. This is load-bearing for `apply-bruno-env.sh` — it reads this output to set the `clientCertificates` domain in `bruno.json`. If the domain is wrong, Bruno silently omits the client cert on every request (see Bruno section above).

Fix: verify `outputs.tf` uses `local.name_prefix` in the Route53 record name, not `var.name`:
```hcl
value = "https://matls-${local.name_prefix}.${var.external_domain_name}"
```

The template was corrected. Any repo bootstrapped before the fix needs `outputs.tf` updated manually and `prepare-bruno-env.sh` re-run.

---

## Terraform / CI ordering

The push order across repos is load-bearing:

```
1. opda-shared-services   → CI publishes new image SHA (note it)
2. opda-shared-infra      → adds module variables (must be ahead of consumers)
3. opda-lr-facade / etc.  → consumes the above; pipeline applies the stack
```

Why: per-API repos consume `opda-shared-infra` modules via `git::https://github.com/Property-Data-Trust-Framework/opda-shared-infra.git//modules/<name>?ref=main`. If a per-API repo plans against a `ref=main` that's behind the local copy, it errors with `Unsupported argument` on whichever variable was just added. Push shared-infra first.

| Pitfall | Notes |
|---|---|
| `Unsupported argument` on `bypass_auth` / `ssm_signing_key_*` | Live module at `ref=main` was behind the local copy — push shared-infra first |
| Unintended cert rotation by Terraform | `ignore_changes = [value]` on HMLR SSM params is required so Terraform doesn't overwrite an out-of-band rotation |
| `terraform destroy` errors over missing credentials | `variables.tf` defaults `default = ""` on credential/image-tag variables so destroy only requires the three structural vars |

---

## Shared VPC

The shared-VPC architecture (one VPC published to SSM, replacing per-API VPCs;
migrated 2026-04-21) is recorded in [[ADR-0007-shared-vpc-ssm|ADR-0007]] — including
the five SSM outputs, the `name_prefix` convention, and the NLB name-length headroom
for ephemeral environments. Assume the post-migration shape for all new work.

---

## AWS quirks

| Quirk | Notes |
|---|---|
| Em dash rejected in SG description | ASCII only. Use `-`. |
| Lambda ENIs release asynchronously | 15–20 minutes after `terraform destroy`. Automated post-destroy checks will false-positive. Either poll until ENIs are gone, or only verify TF-owned resources (Lambda, ECS, NLB, SGs). |
| CloudWatch log groups survive failed destroys | Accumulate silently. Worth including in teardown verification. |
| HMLR test endpoint cert not in Alpine bundle | `hmlr_insecure_skip_verify=true` for non-prod (see HMLR section). |
| NLB DNS doesn't start with `matls-` | Affects mTLS proxy SNI gating (see mTLS section) and Bruno `clientCertificates` domain matching — list `*.eu-west-2.elb.amazonaws.com` until a custom domain is wired up. |

---

## Bootstrap toolchain (`bootstrap-api.sh` + helpers)

The toolchain is in `opda-ops/templates/dotnet/scripts/` (and copied into each API repo). Key invariants from hard lessons:

- `prepare-bruno-env.sh` (needs AWS, writes `scripts/bruno.env`) runs **before** `apply-bruno-env.sh` (no AWS, patches Bruno files). `prepare-` chains directly into `apply-`.
- Provider client ID (server, GitHub secret) and consumer client ID (Bruno) are split: `setup-secrets.sh` handles provider; `update-bruno-env.sh` prompts for consumer.
- `bootstrap-api.sh`'s initial commit uses the user's git credentials (no script override). Bruno collection name derived from repo name.
- Initial commits use the global git identity; an earlier `opda-lr-facade` local git-identity override was removed.
- `scripts/bruno.env` is gitignored across all repos.

---

## Shared proxy — Bruno collection hygiene

All 7 APIs share a single endpoint (`dev.api.smartpropdata.org.uk`). The proxy
routes purely by path prefix ([[ADR-0002-shared-nlb-path-routing-proxy|ADR-0002]]), so **any Bruno request in any collection that
happens to share a prefix with a live API will silently succeed against the
wrong backend** — no 404, no error, nothing to indicate the mismatch.

Discovered when `validate-uprn.bru` (a scaffolding template leftover) was found
in `opda-council-tax-api/bruno/`. Testing it returned 200 — but it was hitting
`opda-uprn-validator` via the `/v1/uprn` prefix, not the council tax API.

**Checklist when bootstrapping a new API:**
- Delete `validate-uprn.bru` (or any other template placeholder request) before
  the first test run — don't leave it in while verifying the new endpoint works.
- Verify each Bruno request targets a path that only the new API owns. Check the
  proxy route table (`/opda/proxy/routes/`) if unsure which prefix wins.
- The scaffolding template Bruno collection should only contain `get-health.bru`
  and `get-token.bru` as starters; the API-specific request is added manually.

---

## API versioning (Raidiam discovery requirement)

> Versioning *convention decision*: [[ADR-0008-api-versioning|ADR-0008]]. The mapping
> below is the live reference of the deployed paths vs the Raidiam portal registrations.

All APIs are versioned. Raidiam's portal generates discovery endpoint URLs from a baseUrl + version + a predefined path template per API family. **Versioning is already applied in code** — the live paths below are what each service serves today; the right-hand column tracks the Raidiam portal registration, which is still pending for the newer APIs.

| API | Live path (in code) | Raidiam portal path |
|---|---|---|
| `opda-lr-facade` | `/opda/official-copies/v1/register-extract` | same (registered) |
| `opda-uprn-validator` | `/v1/uprn/validate/{uprn}` | `/v1/uprn/validate` (registered) |
| `opda-mra-api` | `/v1/coalfield/{uprn}` | `/v1/coalfield` (registered) |
| `opda-os-api` | `/v1/places/find` | `/v1/places/find` (registered) |
| `opda-council-tax-api` | `/v1/council-tax/{uprn}` | TBC — not yet in portal |
| `opda-epc-api` | `/v1/epc/{uprn}` | TBC — not yet in portal |
| `opda-survey-shack-api` | `/v1/documents/{uprn}` | TBC — not yet in portal |

The `.NET` APIs all use a plain `/v1/` prefix (Option A). The facade uses the full `/opda/{family}/v1/{action}` pattern — these are distinct first-path-segment prefixes so shared-proxy routing remains unambiguous.

`/health` endpoints stay unversioned.

**Where versioning lives (touch all of these if a version ever changes):** `Program.cs` endpoint path, `openapi/api.yml` path, API Gateway (redeploys on next push), Bruno `baseUrl` path, shared proxy routing table prefix.

---

## Per-API service-specific notes

### `opda-mra-api` — DynamoDB lookup

- Endpoint: `GET /v1/coalfield/{uprn}` — UPRN regex `^\d{12}$`
- Outcomes: `ON_COALFIELD`, `OFF_COALFIELD`, `UNKNOWN`, 400 (invalid UPRN)
- Table: `opda-mra-api-coalfields-{environment}`, partition key `uprn` (String), `status` attribute (`ON`/`OFF`), `PAY_PER_REQUEST`
- Table is pre-populated by `scripts/import-coalfields.sh` from CSV — **not** managed by the API's Terraform
- IAM data-source needs all four describe permissions for the DynamoDB lookup (initial scaffolding missed some)
- PDTF `RiskArea` wrapper still pending — blocked on schema confirmation from stakeholders

### `opda-os-api` — OS Places proxy

- Endpoint: `GET /v1/places/find?query={q}&maxresults={n}`
- API key in SSM `SecureString` (`/{name-prefix}/os_api_key`), loaded at Lambda startup via `OS_API_KEY_PATH`
- `OS_API_BASE_URL` is a GitHub Actions variable (defaults to `https://api.os.uk/`)
- Internal `OsPlacesResponse` model **not** exposed to callers — mapped to a 7-field `PlaceResult`: `Uprn`, `Address`, `Udprn`, `XCoordinate`, `YCoordinate`, `LocalAuthority`, `PropertyType`
- A standalone direct-OS Bruno collection verifies the API key against `api.os.uk` directly before involving the OPDA stack

### `opda-uprn-validator` — pure-logic

- Endpoint: `GET /v1/uprn/validate/{uprn}` — regex `^\d{12}$` (exactly 12 digits)
- Currently scope `land-registry`. Tighten to `uprn:validate` once Raidiam scope is registered. Same caveat applies to `opda-mra-api`.

---

## How we improved on the Raidiam reference

For context when reading the reference codebase (`opda-lr-facade/raidiam/`), these are areas where our setup is deliberately tighter. When adopting Raidiam patterns wholesale, double-check none of these regressions creep back in. Several of these are recorded as decisions — see [[ADR-0004-public-ca-server-cert|ADR-0004]], [[ADR-0006-provenance-rsa-sha256-jcs|ADR-0006]], [[ADR-0010-github-oidc-aws-auth|ADR-0010]], [[ADR-0011-security-model-mtls-oauth-introspection|ADR-0011]].

| Issue | Raidiam | Ours |
|---|---|---|
| `transport_key` in SSM | plain `String` | `SecureString` |
| Authorizer SSM IAM | `ssm:*` on `*` | scoped to 4 specific parameter ARNs (transport cert/key, ca_trusted_list, signing_key) |
| API GW resource policy | open `execute-api:Invoke` from `*` | conditioned on the VPC endpoint source (`aws:SourceVpce`) |
| AWS auth for CI | long-lived credentials (assumed) | OIDC — no stored secrets |
| ECR image ownership | Raidiam's account | our own account |
| Per-service security groups | one shared `vpc_endpoint_access_sg` across ECS + both Lambdas | dedicated SG per service |
| Target group rename safety | default destroy-then-create | `lifecycle { create_before_destroy }` (added after a rename outage) |
| HMLR username/password sourcing | flowed through CI as Lambda env vars (assumed) | populated to SSM by Terraform from `TF_VAR_hmlr_*`; Lambda fetches via `ssm:GetParameter` at runtime |

VPC parity: we omit two endpoints Raidiam provisions (EC2, EventBridge) and don't set up a VPN Gateway — none of these are referenced by current code, and they'd add cost without value. One regression vs Raidiam to fix: `opda-lr-facade/terraform/ssm.tf` HMLR cert/key resources lack `lifecycle { ignore_changes = [value] }`, so out-of-band rotations get clobbered on next apply (tracked in [[Production-Readiness]]).

---

## Reference materials

- The build was informed by the **Raidiam reference implementation**, kept internally as
  read-only baseline material (not part of the public repos).
- A **standalone OS Places Bruno collection** is kept for verifying the OS API key against
  `api.os.uk` directly before involving the OPDA stack.
