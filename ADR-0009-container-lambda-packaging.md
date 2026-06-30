# ADR-0009: Container Lambdas — Go `scratch`; .NET `provided:al2023` self-contained

- **Status:** Accepted
- **Date recorded:** 2026-06-25

## Context

Both runtimes deploy as container-image Lambdas. The path to a working image was
non-obvious for each — **every base-image option except one fails in a different
way** (the dotnet base image hunts for a class handler; `provided:al2023`'s default
entrypoint refuses to start without a handler arg; scratch images have no CA
bundle). Getting this wrong costs cold-start crashes and `InvalidEntrypoint` errors.

## Decision

**Go Lambdas** (`opda-lr-facade`, authorizer):
- `FROM scratch`, binary named `bootstrap`, explicit `ENTRYPOINT ["/bootstrap"]`.
- `architectures = ["x86_64"]` on the Lambda (matching the build).
- `COPY --from=builder /etc/ssl/certs/ca-certificates.crt …` — scratch has no CA
  bundle, so every outbound HTTPS call fails without it.

**.NET Lambdas** (`opda-uprn-validator`, `opda-mra-api`, `opda-os-api`):
- `FROM provided:al2023` + **self-contained single-file publish** (not the dotnet
  base image, whose entrypoint expects a class handler).
- Override `ENTRYPOINT ["/var/task/bootstrap"]`.
- `-r linux-x64` at **both** `dotnet restore` and `dotnet publish`.
- `-p:InvariantGlobalization=true` (no ICU on `provided:al2023`).

## Consequences

- Reproducible, minimal images on both runtimes.
- .NET authorizer-context scopes come from `HttpContext.User` claims
  (`ScopesFromClaims`), **not** `HttpContext.Items` — `AddAWSLambdaHosting` marshals
  the authorizer context into claims. Using `ScopesFromAuthorizer` 401s on Lambda.
- The full list of base-image pitfalls (with the exact error each produces) stays in
  the packaging tables in [[Key-Learnings]] — this ADR records *the chosen approach*;
  Key-Learnings records *what bit us*.

## Alternatives considered

- **`public.ecr.aws/lambda/dotnet:9` with a class handler** — fails:
  `Unable to load type APIGatewayProxyFunction` against the self-bootstrapping
  hosting model.
- **Go on `provided:al2023`** — entrypoint collision with `bootstrap`; `scratch` is
  cleaner and smaller.
