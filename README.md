# yk-papers-sandbox-ci

A throwaway research prototype. Nothing here is meant for use.

It runs a test matrix on GitHub-hosted runners to see whether a TeX compile can be confined without admin rights:

- **Windows:** an AppContainer (LPAC with `registryRead`) plus a Job object, using a small launcher in `src/`.
  Hosted runners run as administrator, so these runs check OS-version compatibility, not the no-admin claim.
- **macOS:** a Seatbelt profile (`macos/yk.sb`) run with `sandbox-exec`.

Each matrix has two kinds of test: real documents that must compile, and escape attempts that must fail. The escape
attempts read a dummy file outside the sandbox, write outside it, use the network, signal other processes and exhaust
resources. All "secrets" are dummy files created by the workflow.

Workflow: `.github/workflows/sandbox.yml`, run on push to `ci-sandbox` or by hand.
