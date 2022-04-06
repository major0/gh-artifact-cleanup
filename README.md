GitHub Artifact Cleanup Action
==============================

This actions cleans up orphaned artifacts created by [GitHub Actions][].
Orphaned artifacts are artifacts which belong to a [Git][] ref which is
no-longer the tip of any branch. Generally this is a result of a developer
making updates to a [pull-request][], though it also includes artifacts for any
pull-requests which have been accepted into the mainline of development. This
action assumes that any reports/logs/artifacts for a rebased [pull-request][]
can be discarded, and any artifacts for a merged [pull-request][] will be
replaced by new workflow runs when the mainline (master/main/trunc/etc) is
updated.

Basic Usage
-----------

By default the action will inspect all action runs in a repository and delete
all artifacts which are from a git ref which is no longer the head/tip of a
branch. This behavior can be modified via the `newer` and `older` input
parameters.

```yaml
jobs:
  cleanup:
    runs-on: ubuntu-latest
    steps:
    - uses: major0/gh-artifact-cleanup@v1
      token: ${{ secrets.TOKEN }}
      newer: 30      # optional
      older: 7       # optional
      debug: false   # defaults to false
      dry-run: true  # defaults to false
```

See the the [cleanup workflow](.github/workflows/cleanup.yaml) for a complete
example.

Input Parameters
----------------

|   Input   |                             Description                                       | Required |    Default     |
|:----------|:------------------------------------------------------------------------------|:--------:|:--------------:|
| `token`   | Authentication token to use when cleaning repository.                         | `true`   |                |
| `older`   | Limit work to artifacts that are older than the specified number of days old. | `false`  |                |
| `newer`   | Limit to artifacts that are newer than the specified number of days.          | `false`  |                |
| `dry-run` | Do not make any repository changes, only report what would be done.           | `false`  |    `false`     |
| `debug`   | Enable script execution tracing.                                              | `false`  |    `false`     |

[//]: # (references)

[GitHub Actions]: https://docs.github.com/en/actions
[Git]: https://git-scm.com
[pull-request]: https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/about-pull-requests
