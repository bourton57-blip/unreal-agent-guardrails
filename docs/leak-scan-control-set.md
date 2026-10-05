# What the leak scan checks

`tests/Invoke-LeakScan.ps1` is a generic repository hygiene check. It contains
no project-specific identifier and no knowledge of any private codebase, so it
applies unchanged to any public repository.

The pattern list lives inside the script itself. It is described here by
category rather than spelled out, because a document that enumerates the
patterns it searches for is a poor place to keep them.

## Group 1 - secret material

Provider key prefixes, cloud access key identifiers, source-hosting and chat
token prefixes, and the standard private key headers.

## Group 2 - hardcoded credentials

Assignments that pair a credential-shaped keyword with a literal value, such as
an API key, access token, client secret or connection string.

## Group 3 - personal paths

Absolute user home directories appearing inside file contents, on both Unix and
Windows layouts.

## Group 4 - sensitive files

Environment files, credential files, private key and certificate extensions.

## Group 5 - engine asset containers

Binary engine content extensions that are normally purchased or marketplace
material and therefore not redistributable. A plain text descriptor is
allowed, since synthetic fixtures legitimately include one.

## Group 6 - repository size

Files above a configurable threshold, which bloat clones and usually indicate
missing Git LFS configuration.

## Declared exclusions

Two, both stated in the script:

- the `.git` directory, which is local metadata and never published;
- the script itself, since a scanner necessarily contains the strings it
  searches for.

## Project-specific scanning

A maintainer who needs checks tied to a private project keeps them in a
separate scan that is not committed. This is the arrangement used by the
project that produced this toolkit, and it is the reason the public scanner
here contains nothing project-specific.
