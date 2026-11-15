# Optional GitHub Actions workflow

`github-actions.yml` tests C++ normally and under ASan/UBSan, and Julia on
1.10 and the latest stable release. To enable it, copy it to
`.github/workflows/ci.yml` and push using credentials authorized for workflows.

The initial publication token did not have GitHub's `workflow` OAuth scope.
Consequently this release includes the configuration as an inactive template;
GitHub-hosted CI has not run. The published verification results are from the
local reproducible tests, including sanitizers and the complete prepared corpus.
