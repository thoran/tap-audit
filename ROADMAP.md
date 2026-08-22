# tap-audit Roadmap

Date: 20260823

Jobs are in TODO.txt. What is here is undecided: questions to be answered rather
than work to be done, which is why they are prose and the jobs are a list.

## Open questions

### Whether this is a tap auditor or a repository auditor which a tap auditor calls

The name says tap and the balance says otherwise. Of the fourteen per-formula
checks, one reads the formula alone, four read the repository alone, and nine
take both. The checks added most recently — the standard files, the summary
provenance — barely consult the formula at all: it supplies the name and nothing
else. What has been built is closer to a repository auditor which uses the tap as
its index of which repositories to audit.

That matters because anything not in the tap gets nothing. Fifteen repositories
declared a licence with no LICENSE file and sat that way unreported, while the
tap's twenty were swept, because they have no formula and so are not in the
index.

**If it splits, the seam is intrinsic against relational**, and not repository
against tap, which is the obvious cut and the wrong one. A repository auditor
asks whether a repository is self-consistent: CHANGELOG against commits,
`VERSION.rb` against the script header, tags against the branch, the standard
files present. None of that needs a formula. What remains here is the relational
question — whether the formula agrees with what the repository says: the pin, the
version, the install lines against the tracked directories, the interpreter
against `depends_on`, and what origin serves.

The name stays as it is for now. What is undecided is whether the split happens
at all, and the cost is the spec rather than the tool: most of the eighty-nine
examples build a formula and a tap directory in order to exercise something which
only reads a repository.

### Whether pinning is policy

`pin_finding` reports a `url` naming no tag as taking the default branch whatever
the version says, which is how mercurial's keg came to contain 0.11.0 while
calling itself 0.11.1. It says this of all twenty formulae and will go on saying
it until each names a tag.

So the tool makes the case, and loudly. What is unsettled is whether to act on
it, which is a question about the tap rather than about this. Pinning also
introduces a fault of its own — a tag which moves under a formula, which no
reading of a clone can see — and `remote_findings` was written before the sweep
for that reason rather than after it.

### Whether the standard files belong here at all

`standard_file_findings` reports a missing README, LICENSE, License section,
CHANGELOG or `.gitignore`. None of those has anything to do with a tap, and every
one of them is true of any repository you release from. They are here because the
tap is where the list of repositories was, which is the same reasoning as the
first question above and probably has the same answer.

### What to do about a fork

`orphan_findings` reports a tag naming a commit outside the branch released from.
A fork carries its upstream's tags, which by that definition are all orphaned and
are meant to be: rpm has 87 of them. Whether the answer is an exemption list, a
heuristic, or leaving forks out of the index is open, and it is the same question
`--branch` raises for a repository which does not release from master.
