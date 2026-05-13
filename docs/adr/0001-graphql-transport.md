# ADR 0001: GraphQL transport

Status: accepted, 2026-05-13

## Context

`RepoBarCore` makes a small number of GitHub GraphQL calls (repo enrichment, contribution history, recent activity). Upstream (`steipete/RepoBar`) used `apollo-ios` 2.x as a dependency, kept primarily for the `apollo-ios-cli` codegen workflow — no Swift file in `Sources/` ever imports the `Apollo` module at runtime. The GraphQL transport in `Sources/RepoBarCore/API/GraphQLClient.swift` is hand-rolled: it sends GraphQL queries as plain POSTs against `https://api.github.com/graphql` and decodes responses with `JSONDecoder` into types `RepoBarCore` owns.

When porting to Linux we probed whether `apollo-ios` 2.0.x would build on Swift 6.2 with `swift-corelibs-foundation`. It does not. The compiler surfaces roughly 50 errors across the Apollo runtime, all stemming from URL-machinery that does not exist on swift-corelibs-foundation:

- `URLRequest`, `URLSession.AsyncBytes`, `HTTPURLResponse.statusCode`, `HTTPURLResponse.value(forHTTPHeaderField:)`, the `MultipartHeaderComponents` helper, and so on. Each of these has moved to the `FoundationNetworking` module on Linux but Apollo's source still references them through `Foundation`.
- `HTTPURLResponse` becomes `AnyObject` on Linux, which breaks every Sendable-conforming struct that captures it.

Fixing Apollo upstream is a significant body of work and outside our scope.

## Decision

Drop `apollo-ios` from `Package.swift` entirely. Keep the existing hand-rolled `GraphQLClient` actor as the only GraphQL transport across macOS and Linux. The actor is small (`~`200 LOC), uses only `URLSession` + `Foundation`/`FoundationNetworking`, and matches the shape of the GitHub responses we actually consume.

The codegen workflow (`apollo-ios-cli`, `apollo-codegen.json`) remains on disk for reference but is not invoked. Generated types are not committed and not required at build time.

## Consequences

- Linux build resolves no Apollo runtime; no `URLRequest` / `HTTPURLResponse` Sendable problems.
- macOS build no longer downloads/builds Apollo as a SwiftPM dependency, which speeds clean builds on both platforms by tens of seconds.
- If a future feature needs Apollo-class machinery — multipart subscriptions, Apollo cache, codegen-driven type safety — we revisit by either adding back a patched Apollo (likely a fork) or replacing the hand-rolled client with `swift-graphql` or similar.
- We lose strongly-typed query objects that codegen would have provided. We mitigate this by keeping query strings and response types under `Sources/RepoBarCore/API/` with hand-maintained Decodable conformances and review at PR time.

## Verification

`repobar activity <user> --plain --limit N` exercises the hand-rolled `GraphQLClient` end-to-end and works on Linux against the live GitHub API (verified on Arch with Swift 6.2-RELEASE).
