# tap-audit

## Description

Reports what each formula in a Homebrew tap has drifted from.

It reads three things which are meant to agree — the repository, the formula, and what the search path actually answers with — and says where they do not. Each check corresponds to something which went wrong once and was found by hand.

It exits 1 where anything was found, so it can gate a release.


## Installation

### 0. Have a recent version of Ruby installed

### 1. Manually

```shell
git clone https://github.com/thoran/tap-audit
cp ./tap-audit/bin/tap-audit to your preferred executable path
chmod +x /path/to/tap-audit
```


## Usage

```shell
$ tap-audit
$ tap-audit --origin
$ tap-audit --formulae ~/homebrew-tap --repositories ~/code
```

| Option | Takes | What it does |
| --- | --- | --- |
| `-c`, `--config` | file | Where the configuration is, `~/.config/tap-audit/config.json` by default |
| `-r`, `--repositories` | directory | Where the source repositories are |
| `-f`, `--formulae` | directory | Where the formulae are |
| `-s`, `--search-path` | colon-separated directories | Searched in order, `$PATH` by default |
| `-b`, `--brew-prefix` | directory | Where Homebrew keeps `bin` |
| `-B`, `--branch` | name | The branch each repository releases from, `master` by default |
| `-o`, `--origin` | — | Ask origin what a pinned build would fetch, one call per repository |
| `-h`, `--help` | — | Show the help |

Everything but `--origin` reads the disc, so a run is quick and offline. `--origin` is asked for rather than assumed because it is the only part which touches the network.


## Configuration

A tap is a repository, so with no configuration at all `tap-audit` is run from within one and reads what it installs from beside it — `.` for the formulae and `..` for the repositories.

Where they sit elsewhere, say so once rather than upon every run:

```json
{
  "repositories": "~/code/repositories",
  "formulae": "~/code/repositories/homebrew-tap"
}
```

in `~/.config/tap-audit/config.json`, or wherever `--config` names. A switch overrides the configuration, the configuration overrides the default, and a missing file is no error.


## The checks

Per formula:

| check | what it catches |
| --- | --- |
| `version_finding` | the formula's version against the CHANGELOG's |
| `secondary_version_findings` | a version stated again in `VERSION.rb` or the script header |
| `pin_finding` | a `url` naming no tag, or one the repository lacks |
| `pin_version_finding` | a pinned tag naming a release other than the version |
| `directory_findings` | a directory tracked in the repository and named by no install line |
| `interpreter_finding` | `bin/x` is a ruby script and the formula `depends_on` no ruby |
| `unreadable_changelog_finding` | a CHANGELOG stating no summary in the form at all |
| `summary_findings` | a version's summary in the CHANGELOG against the one in its commit |
| `untagged_findings` | a version the repository states with no tag |
| `orphan_findings` | a tag naming a commit outside the branch released from |
| `remote_findings` | what a pinned build would fetch from origin |
| `standard_file_findings` | a missing README, LICENSE, License section, CHANGELOG, `.gitignore` or `license` |
| `homepage_finding` | `homepage` and `url` naming different repositories |
| `unrecognised_findings` | formula idioms it cannot parse, said aloud rather than passed over |
| `unstaged_resource_finding` | resources declared and installed by nothing in `def install` |
| `unqualified_dependency_findings` | a dependency named without qualification |
| `shadow_finding` | something earlier on the search path answering to the name |

And two reported apart from the formulae, being faults of the tap rather than of any one formula in it:

| check | what it catches |
| --- | --- |
| `resource_findings` | the same gem pinned at more than one version across the tap |
| `readme_findings` | the tap's own README naming a formula it no longer holds, or failing to name one it does |


## The three which are not obvious

**`shadow_finding`** is the consumer half. A formula can be correct in every other respect and still never be what runs: a gem shim in `~/.gem` or a copy in `~/bin` sits earlier on the path and answers to the name instead. It searches only the directories ahead of Homebrew's own `bin`, on the reasoning that a formula installs there and nowhere earlier, so anything of the same name found before it is what the name actually runs.

**`orphan_findings`** does not stop at reachability. A tag naming a commit off the branch still resolves — the tag is itself a ref, so the commit survives garbage collection — and a fetch of it never fails. What decides whether it matters is the tree: identical, and the tag is bookkeeping left by an amended message; different, and the repository and the tag disagree about what that version was, so a pin there installs the version a rewrite abandoned, permanently, a pin not drifting.

**`remote_findings`** asks origin, because a pinned `url` is fetched from origin and nowhere else. Every other check here reads a clone, which can be in perfect order while origin serves something else — the state fifty-eight tags across eight repositories were in on 20260822, none of them visible from a clone.


## The fault it caught in itself

Recorded in the source at 0.3.0, and worth carrying into anything else which checks:

> A repository without commits tracks nothing, so `ls-files` answers empty and the directory check passes upon having found nothing rather than upon there being nothing to find.

An auditor which passes because it looked and found nothing, rather than because there was nothing to find, is the failure mode of every checker.


## Related tools

- [changelogger](https://github.com/thoran/changelogger), which writes the CHANGELOG this repository's own history was reconstructed with.


## Contributing

1. Fork it: `https://github.com/thoran/tap-audit/fork`
2. Create your feature branch: `git checkout -b my-new-feature`
3. Commit your changes: `git commit -am 'Add some feature'`
4. Push to the branch: `git push origin my-new-feature`
5. Create a new pull request


## License

MIT
