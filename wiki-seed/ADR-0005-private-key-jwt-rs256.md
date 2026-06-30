# ADR-0005: Raidiam client auth via `private_key_jwt` using RS256

- **Status:** Accepted
- **Date recorded:** 2026-06-25

## Context

The Raidiam token endpoint supports `private_key_jwt` and `tls_client_auth`. The
OpenID discovery document advertises **`PS256`** as the signing algorithm — **but
Raidiam confirmed that `RS256` is what they actually accept.** Cert-bound access
tokens are enabled (`tls_client_certificate_bound_access_tokens: true`), so the
`cnf.x5t#S256` claim binds the token to the client cert.

## Decision

Authenticate the authorizer to Raidiam using **`private_key_jwt`**, signing the
`client_assertion` JWT with **RS256** (not the discovery-advertised PS256). The
authorizer **omits the `kid` header**, matching Raidiam's own reference script.

The JWT the authorizer builds on each call:

```
header   { "alg": "RS256", "typ": "JWT" }
payload  { "iss": "<client_id_url>", "sub": "<client_id_url>",
           "aud": "<introspection_endpoint>",
           "jti": "<uuid>", "iat": <now>, "exp": <now + 300s> }
```

## Consequences

- Works despite the discovery/runtime mismatch. **This ADR exists primarily so
  nobody "corrects" the algorithm back to PS256** to match the discovery doc.
- The provider (server) identity is **unique per API** — each API has its own
  Raidiam application registration, its own client-ID URL (`OAUTH_CLIENT_ID`), and
  its own `rtssigning` key. Copying a signing key between APIs causes introspection
  failures.
- The consumer (client) identity used for testing (Bruno) is **shared** and can be
  copied between API repos.
- Raidiam access tokens last ~5 minutes; re-mint on 401 during testing.

## Alternatives considered

- **PS256 (as advertised by discovery)** — rejected: confirmed rejected by the
  Raidiam token endpoint in practice.
- **`tls_client_auth`** instead of `private_key_jwt` — viable, but `private_key_jwt`
  matches the Raidiam reference flow and decouples client auth from the transport
  cert.
