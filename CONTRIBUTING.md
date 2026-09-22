# Contributing to Omac

Develop changes in a branch and submit a pull request with the problem, the fix,
and the checks you ran. Keep changes small enough to review independently.

## Local build

Use a Mac with the prerequisites in DISTRIBUTION.md. Run:

```sh
python3 -m unittest discover -p 'test_*.py'
./package.sh
python3 tests/verify_installer.py
```

Move any existing `dist` directory aside before packaging. The package records its
source commit in `Omac.app/Contents/Info.plist`. Build from a committed checkout so
that reviewers can reproduce the source version. Signing credentials stay on the
builder's Mac; contributors do not need the maintainer's private keys.

## Protect running work

- Never close terminal sessions to test an upgrade.
- Keep settings and machine-specific connection paths in Application Support,
  outside the signed app and the repository.
- Use isolated state directories for automated tests.
- Verify actual page switching, new-terminal creation, and app focus separately
  from compilation and unit tests.
- Test a failed install and rollback as well as a successful update.
- Do not reset permissions, reboot, or publish as a side effect of a build.

## Bug reports

Include the Omac version, macOS version, monitor setup (including virtual
displays), shortcut, expected behavior, and what happened. Say whether input came
from the Mac's own keyboard or Screen Sharing. Remove personal window titles,
connection files, credentials, and private paths before sharing diagnostics.

Maintainers review contributions before including them in a release. Contributions
are provided under GPL-3.0-only, the same license as Omac. Contributors retain
copyright in their contributions; submitting a contribution does not transfer
ownership. Only contribute material you have the right to license this way.
