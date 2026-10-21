# Release notes

Each GitHub release of PHMN is written in one fixed shape, because the app reads it: **About › What's new** fetches the releases of this repository and shows any release the
installed build does not carry, so a release appears in the app the moment it is published, with no new build.

```markdown
## PHMN <version>

One sentence that sums the release up. It becomes the card's title.

### New / Enhancement
- **A short name.** What is new or what changed in a feature that already existed, in a sentence or two. Markdown bold and italics are fine.
- ...

### Bug Fixing
- What was wrong and what happens now.
- ...

### Install
(anything else: the installing text, notes, credits. The app ignores every section other than the two above.)
```

Rules:

- **Two categories only.** *New / Enhancement* is a new feature or a change to an existing one (a redesign, a faster flow, a clearer screen). *Bug Fixing* is something that was broken
  and now works. A release can have either one or both; a category with nothing in it is left out.
- One bullet is one thing a person would notice. Start with a bold name, then say what it does or what was wrong. No issue numbers, no commit hashes.
- The older heading `### What's new` is still read as New / Enhancement, so releases written before this format keep showing.
- Drafts and pre-releases are not shown in the app.
- The version number is not repeated in the README or the docs; it lives in the release title and in `project.yml`.

[`NEXT.md`](NEXT.md) holds the notes of the release being prepared. Copy it into the GitHub release when it ships, then replace it with a clean template.

NOOP's own release notes, which this fork inherits, are in [docs/releases](../releases).

**The sideload source** is `altstore-source.json` at the root of this repository (served from the `phm` branch). When a release ships, add its entry to `versions` (version, build, date, the release's IPA URL and its size in bytes) and update the top-level fields to match, in the same commit that bumps `project.yml`.
