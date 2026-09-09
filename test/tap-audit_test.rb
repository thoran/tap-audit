# tap-audit_test.rb

# 20260909
# 0.8.1

# The tap under test is built rather than borrowed.  tap-audit reads two
# directories — the formulae and the repositories beside them — and both are
# made here, per example, so that every state the tool distinguishes is stated
# outright instead of being whichever states the real tap happens to hold.
#
# Run as a subprocess and asserted upon by what it printed, --formulae and
# --repositories being the whole of the interface and already there.

require 'minitest/autorun'
require 'fileutils'
require 'open3'
require 'tmpdir'

# The fixtures are built with git, which reads the machine's configuration before
# anything here has a say, and borrowing it undoes the paragraph above.
# tag.gpgSign is true on the machine this runs on, which makes a bare
# `git tag v1.0.0` fail with "no tag message?", so no fixture carried a tag and
# every check which reads one failed — 23 of the 91 examples, the whole of the
# origin check among them, found on 20260909 and red at every commit tested back
# to 0.14.1.  How much further back it goes depends upon when tag.gpgSign was
# set, which nothing records.  Both configuration files are therefore pointed at
# nothing, for this process and for the subprocess it runs.  Identity is passed
# per commit already, which is why that much survived.
ENV['GIT_CONFIG_GLOBAL'] = File::NULL
ENV['GIT_CONFIG_SYSTEM'] = File::NULL

BIN = ENV['TAP_AUDIT'] || File.expand_path('../bin/tap-audit', __dir__)

# A formula with the parts each example varies and defaults for the rest, so
# that an example states the one thing it is about.
def formula_source(name, version: '1.0.0', tag: nil, install: nil, resources: {}, depends_on: ['ruby'], homepage: nil, license: 'MIT')
  url = tag ? "url 'https://github.com/thoran/#{name}.git', tag: '#{tag}'" : "url 'https://github.com/thoran/#{name}.git'"
  body = install || "bin.install 'bin/#{name}'"
  declarations = resources.collect{|gem_name, gem_version| resource_source(gem_name, gem_version)}.join
  dependencies = depends_on.collect{|dependency| "  depends_on '#{dependency}'\n"}.join
  header = "  homepage 'https://github.com/thoran/#{homepage || name}'\n  version '#{version}'\n"
  header += "  license '#{license}'\n" if license
  "class #{name.capitalize} < Formula\n#{header}\n  #{url}\n\n#{dependencies}\n#{declarations}  def install\n#{body.lines.collect{|l| '    ' + l}.join}\n  end\nend\n"
end

def resource_source(gem_name, gem_version)
  "  resource '#{gem_name}' do\n    url 'https://rubygems.org/downloads/#{gem_name}-#{gem_version}.gem'\n  end\n\n"
end

def git(directory, *arguments)
  system('git', '-C', directory, *arguments, out: File::NULL, err: File::NULL)
end

# bin/<name> with a first line, the interpreter check reading no further.
# requires: is what the program asks for itself, which is what tells a gem two
# formulae reach directly from one which only a single formula reaches.
def write_binary(directory, name, shebang, requires: [])
  FileUtils.mkdir_p(File.join(directory, 'bin'))
  body = requires.collect{|required| "require '#{required}'\n"}.join
  File.write(File.join(directory, 'bin', name), "#{shebang}\n# #{name}\n#{body}")
end

# A repository with a commit unless one is not wanted, ls-files reporting
# nothing before the first commit and the directory check then having nothing to
# miss, which is a state of its own and tested below.
# An amend leaves any tag upon the commit it replaced, naming code outside the
# branch: git status says nothing, git tag still lists it, and it still resolves.
# :message keeps the tree and changes only what the commit says, which is the
# harmless half; :content changes the tree, which is the half a pin would ship;
# :version leaves the branch saying nothing about that version at all.
def orphan_by(directory, how)
  case how
  when :message
    git(directory, '-c', 'user.email=s@e', '-c', 'user.name=s', 'commit', '--quiet', '--amend', '-m', '1.0.0: whatever it was, reworded.')
  when :content
    File.write(File.join(directory, 'changed'), 'x')
    git(directory, 'add', '.')
    git(directory, '-c', 'user.email=s@e', '-c', 'user.name=s', 'commit', '--quiet', '--amend', '--no-edit')
  when :version
    git(directory, '-c', 'user.email=s@e', '-c', 'user.name=s', 'commit', '--quiet', '--amend', '-m', 'no version in this one')
  end
end

# The files every repository is meant to carry, written unless an example is
# about one of them being absent, so that a fixture states the one thing it
# varies rather than every standard file over again.
def write_standard_files(directory, readme: true, licence: true, gitignore: true, readme_body: nil)
  File.write(File.join(directory, 'README.md'), readme_body || "# thing\n\n## Description\n\nWhatever it does.\n\n\n## License\n\nMIT\n") if readme
  File.write(File.join(directory, 'LICENSE'), "MIT License\n\nCopyright (c) 2026 thoran\n") if licence
  lines = gitignore == true ? 47 : gitignore
  File.write(File.join(directory, '.gitignore'), Array.new(lines){|i| "# line #{i}"}.join("\n") + "\n") if lines
end

def make_repository(root, name, files: [], changelog: nil, tags: [], commits: true, shebang: nil, commit_summary: :from_changelog, extra_commits: [], old_changelog: false, orphan: nil, branch: nil, standard: {}, readme_body: nil, version_file: nil, header_version: nil, dated: nil, changelog_later: nil, requires: [])
  directory = File.join(root, name)
  FileUtils.mkdir_p(directory)
  write_standard_files(directory, readme_body: readme_body, **standard)
  files.each{|f| FileUtils.mkdir_p(File.dirname(File.join(directory, f))); FileUtils.touch(File.join(directory, f))}
  write_binary(directory, name, shebang, requires: requires) if shebang || !requires.empty?
  if version_file
    path, stated = version_file
    FileUtils.mkdir_p(File.dirname(File.join(directory, path)))
    File.write(File.join(directory, path), "class Thing\n  VERSION = '#{stated}'\nend\n")
  end
  if header_version
    FileUtils.mkdir_p(File.join(directory, 'bin'))
    File.write(File.join(directory, 'bin', name), "#!/usr/bin/env ruby\n# #{name}\n\n# 20260823\n# #{header_version}\n")
  end
  File.write(File.join(directory, 'CHANGELOG'), "# CHANGELOG\n\n## 20260817\n\n#{changelog}: whatever it was.\n") if changelog
  File.write(File.join(directory, 'CHANGELOG'), "# CHANGELOG\n\n1.0.0 - 20260821\n\nWhatever it was.\n") if old_changelog
  git(directory, 'init', '--quiet') || (FileUtils.mkdir_p(directory) && git(directory, 'init', '--quiet'))
  return unless commits
  git(directory, 'add', '.')
  message = commit_summary == :from_changelog ? (changelog ? "#{changelog}: whatever it was." : 'in') : commit_summary
  dating = dated ? ['--date', dated] : []
  git(directory, '-c', 'user.email=s@e', '-c', 'user.name=s', 'commit', '--quiet', *dating, '-m', message)
  # The CHANGELOG written after the commit it describes, which is what a
  # backfilled record is: moby's entries are of 2026 and its commits of 2024.
  if changelog_later
    File.write(File.join(directory, 'CHANGELOG'), "# CHANGELOG\n\n## 20260817\n\n#{changelog_later}: whatever it was.\n")
    git(directory, 'add', '.')
    git(directory, '-c', 'user.email=s@e', '-c', 'user.name=s', 'commit', '--quiet', '-m', '+ CHANGELOG')
  end
  extra_commits.each do |summary|
    File.write(File.join(directory, 'again'), summary)
    git(directory, 'add', '.')
    git(directory, '-c', 'user.email=s@e', '-c', 'user.name=s', 'commit', '--quiet', '-m', summary)
  end
  tags.each{|t| git(directory, 'tag', t)}
  orphan_by(directory, orphan) if orphan
  git(directory, 'branch', '--move', branch) if branch
end

def audit(*arguments)
  stdout, stderr, status = Open3.capture3(BIN, *arguments)
  [stdout + stderr, status.exitstatus]
end

# A formula beside a repository which has been git init'd and left alone.
def commitless(version: '1.0.0', files: ['bin/thing', 'lib/Thing.rb'])
  {
    formulae: {'thing' => formula_source('thing', version: version, tag: 'v1.0.0', install: "bin.install 'bin/thing'")},
    repositories: {'thing' => {files: files, changelog: '1.0.0', commits: false}},
  }
end

# The tap's own README states its formulae twice, as a line to run and as a link
# to the source, and the check reads both.  Written to agree unless an example
# gives it something else to say.
def write_tap_readme(tap, names, installed: nil, sourced: nil)
  installs = (installed || names).collect{|name| "$ brew install #{name}"}.join("\n")
  sources = (sourced || names).collect{|name| "[#{name}](https://github.com/thoran/#{name})"}.join(",\n")
  File.write(File.join(tap, 'README.md'), "# homebrew-tap\n\n## Usage\n\n```shell\n#{installs}\n```\n\n## Sources\n\n#{sources}\n")
end

def in_fixture(formulae: {}, repositories: {}, arguments: [], tap_readme: nil)
  Dir.mktmpdir do |root|
    tap = File.join(root, 'tap')
    repositories_directory = File.join(root, 'repositories')
    FileUtils.mkdir_p([tap, repositories_directory])
    formulae.each{|name, source| File.write(File.join(tap, "#{name}.rb"), source)}
    tap_readme ? write_tap_readme(tap, formulae.keys, **tap_readme) : write_tap_readme(tap, formulae.keys)
    repositories.each{|name, options| make_repository(repositories_directory, name, **options)}
    stdout, stderr, status = Open3.capture3(BIN, '--formulae', tap, '--repositories', repositories_directory, '--search-path', '', *arguments)
    yield stdout + stderr, status.exitstatus
  end
end

# A def install which both stages its resources and installs the tree, for the
# examples which declare a resource and are not about whether it is staged.
STAGING = "resources.each do |r|\n  r.fetch\nend\nlibexec.install 'bin', 'lib'"

# One formula and one repository agreeing about everything, which every example
# below varies exactly one thing from.
def agreeing(install: nil, version: '1.0.0', resources: {})
  {
    formulae: {'thing' => formula_source('thing', version: version, tag: 'v1.0.0', install: install, resources: resources)},
    repositories: {'thing' => {files: ['bin/thing', 'lib/Thing.rb'], changelog: '1.0.0', tags: ['v1.0.0']}},
  }
end

describe 'a formula and repository which agree' do
  it 'reports nothing and exits 0' do
    in_fixture(**agreeing(install: "libexec.install 'bin', 'lib'")) do |output, status|
      _(output).wont_match(/version:|url names|is in the repository|unrecognised/)
      _(status).must_equal 0
    end
  end
end

describe 'the version check' do
  it 'says nothing where the formula and the CHANGELOG agree' do
    in_fixture(**agreeing(install: "libexec.install 'bin', 'lib'")) do |output, _status|
      _(output).wont_include 'version:'
    end
  end

  it 'reports both where they disagree' do
    in_fixture(**agreeing(install: "libexec.install 'bin', 'lib'", version: '0.9.0')) do |output, status|
      _(output).must_include 'the formula says 0.9.0 and the CHANGELOG says 1.0.0'
      _(status).must_equal 1
    end
  end

  # A repository with no CHANGELOG is not a repository which disagrees.
  it 'says nothing where there is no CHANGELOG to compare against' do
    in_fixture(
      formulae: {'thing' => formula_source('thing', tag: 'v1.0.0', install: "libexec.install 'bin', 'lib'")},
      repositories: {'thing' => {files: ['bin/thing', 'lib/Thing.rb'], tags: ['v1.0.0']}},
    ) do |output, _status|
      _(output).wont_include 'version:'
    end
  end
end

describe 'the summary check' do
  it 'says nothing where the commit and the CHANGELOG agree' do
    in_fixture(**agreeing(install: "libexec.install 'bin', 'lib'")) do |output, _status|
      _(output).wont_include 'summary:'
    end
  end

  it 'reports both texts where they differ, a line apiece' do
    in_fixture(
      formulae: {'thing' => formula_source('thing', tag: 'v1.0.0', install: "libexec.install 'bin', 'lib'")},
      repositories: {'thing' => {files: ['bin/thing'], changelog: '1.0.0', tags: ['v1.0.0'], commit_summary: '1.0.0: something else entirely.'}},
    ) do |output, status|
      _(output).must_include %{commit     "1.0.0: something else entirely."}
      _(output).must_include %{CHANGELOG  "1.0.0: whatever it was."}
      _(status).must_equal 1
    end
  end

  # A release which recorded itself inconsistently, both texts having been
  # written at once, which is a different fault from the one below.
  it 'says where both were written in one commit' do
    in_fixture(
      formulae: {'thing' => formula_source('thing', tag: 'v1.0.0', install: "libexec.install 'bin', 'lib'")},
      repositories: {'thing' => {files: ['bin/thing'], changelog: '1.0.0', tags: ['v1.0.0'], commit_summary: '1.0.0: something else entirely.'}},
    ) do |output, _status|
      _(output).must_match(/summary: 1\.0\.0 disagrees, both written in \h+/)
    end
  end

  # moby's case: the commits are of 2024 and the entries were reconstructed in
  # 2026, so the record disagreeing with the log was written two years after it.
  it 'orders them oldest first where the CHANGELOG was written later' do
    in_fixture(
      formulae: {'thing' => formula_source('thing', tag: 'v1.0.0', install: "libexec.install 'bin', 'lib'")},
      repositories: {'thing' => {files: ['bin/thing'], tags: ['v1.0.0'], commit_summary: '1.0.0: something else entirely.', dated: '2024-06-05', changelog_later: '1.0.0'}},
    ) do |output, _status|
      _(output).must_include 'summary: 1.0.0 disagrees, oldest first'
      _(output).must_include %{2024-06-05  commit     "1.0.0: something else entirely."}
      _(output).must_match(/\d{4}-\d{2}-\d{2}  CHANGELOG  "1\.0\.0: whatever it was\."/)
    end
  end

  # The commit predating the convention is not the CHANGELOG disagreeing with
  # it, but it is still a version nothing in the log accounts for.
  it 'reports a version the CHANGELOG states and no commit says' do
    in_fixture(
      formulae: {'thing' => formula_source('thing', tag: 'v1.0.0', install: "libexec.install 'bin', 'lib'")},
      repositories: {'thing' => {files: ['bin/thing'], changelog: '1.0.0', tags: ['v1.0.0'], commit_summary: 'in'}},
    ) do |output, _status|
      _(output).must_include 'summary: 1.0.0 is in the CHANGELOG and no commit says it'
    end
  end

  # moby's case: two commits carry 0.8.0, so the version names two states and
  # neither the tag nor the entry says which.
  it 'reports a version carried by more than one commit' do
    in_fixture(
      formulae: {'thing' => formula_source('thing', tag: 'v1.0.0', install: "libexec.install 'bin', 'lib'")},
      repositories: {'thing' => {files: ['bin/thing'], changelog: '1.0.0', tags: ['v1.0.0'], extra_commits: ['1.0.0: whatever it was.']}},
    ) do |output, _status|
      _(output).must_include 'summary: 1.0.0 is the version of 2 commits'
    end
  end

  # weblink's case: the older form states the version and date upon one line and
  # the summary upon the next, so nothing matches and every commit looks orphaned.
  it 'reports the CHANGELOG once where it states no summary in the form' do
    in_fixture(
      formulae: {'thing' => formula_source('thing', tag: 'v1.0.0', install: "libexec.install 'bin', 'lib'")},
      repositories: {'thing' => {files: ['bin/thing'], tags: ['v1.0.0'], old_changelog: true, commit_summary: '1.0.0: whatever it was.'}},
    ) do |output, _status|
      _(output).must_include 'summary: the CHANGELOG states no summary in the form'
      _(output.scan('summary:').length).must_equal 1
    end
  end

  it 'says nothing where there is no CHANGELOG at all' do
    in_fixture(
      formulae: {'thing' => formula_source('thing', tag: 'v1.0.0', install: "libexec.install 'bin', 'lib'")},
      repositories: {'thing' => {files: ['bin/thing'], tags: ['v1.0.0'], commit_summary: '1.0.0: whatever it was.'}},
    ) do |output, _status|
      _(output).wont_include 'summary:'
    end
  end
end

describe 'the untagged version check' do
  it 'says nothing where every version has a tag' do
    in_fixture(**agreeing(install: "libexec.install 'bin', 'lib'")) do |output, _status|
      _(output).wont_include 'tags:'
    end
  end

  # The one which stops the formula being pinned, reported apart from the rest.
  it 'reports the declared version having no tag' do
    in_fixture(
      formulae: {'thing' => formula_source('thing', tag: 'v1.0.0', install: "libexec.install 'bin', 'lib'")},
      repositories: {'thing' => {files: ['bin/thing'], changelog: '1.0.0', tags: []}},
    ) do |output, status|
      _(output).must_include 'tags: the formula declares 1.0.0 and the repository has no tag for it'
      _(status).must_equal 1
    end
  end

  # moby's case: thirty-seven untagged versions would be thirty-seven findings,
  # and the count with its range says the same thing in one line.
  it 'collapses the older ones into a count and a range' do
    in_fixture(
      formulae: {'thing' => formula_source('thing', version: '0.3.0', tag: 'v0.3.0', install: "libexec.install 'bin', 'lib'")},
      repositories: {'thing' => {files: ['bin/thing'], changelog: '0.3.0', tags: ['v0.3.0'],
        extra_commits: ['0.1.0: whatever it was.', '0.2.0: whatever it was.']}},
    ) do |output, _status|
      _(output).must_include 'tags: 2 versions have no tag, 0.1.0 to 0.2.0'
      _(output).wont_include 'declares 0.3.0 and the repository has no tag'
    end
  end

  it 'names the version where only one lacks a tag' do
    in_fixture(
      formulae: {'thing' => formula_source('thing', version: '0.2.0', tag: 'v0.2.0', install: "libexec.install 'bin', 'lib'")},
      repositories: {'thing' => {files: ['bin/thing'], changelog: '0.2.0', tags: ['v0.2.0'],
        extra_commits: ['0.1.0: whatever it was.']}},
    ) do |output, _status|
      _(output).must_include 'tags: 0.1.0 has no tag'
    end
  end

  # A tag naming no version is not a version without a tag.
  it 'passes over tags which are not versions' do
    in_fixture(
      formulae: {'thing' => formula_source('thing', tag: 'v1.0.0', install: "libexec.install 'bin', 'lib'")},
      repositories: {'thing' => {files: ['bin/thing'], changelog: '1.0.0', tags: ['v1.0.0', 'accidental-fork']}},
    ) do |output, _status|
      _(output).wont_include 'tags:'
    end
  end
end

describe 'the tag check' do
  it 'says nothing where the url names a tag the repository has' do
    in_fixture(**agreeing(install: "libexec.install 'bin', 'lib'")) do |output, _status|
      _(output).wont_include 'url names'
    end
  end

  it 'reports a url which names no tag' do
    in_fixture(
      formulae: {'thing' => formula_source('thing', install: "libexec.install 'bin', 'lib'")},
      repositories: {'thing' => {files: ['bin/thing', 'lib/Thing.rb'], changelog: '1.0.0'}},
    ) do |output, _status|
      _(output).must_include 'url names no tag'
    end
  end

  it 'reports a tag the repository does not have' do
    in_fixture(
      formulae: {'thing' => formula_source('thing', tag: 'v9.9.9', install: "libexec.install 'bin', 'lib'")},
      repositories: {'thing' => {files: ['bin/thing', 'lib/Thing.rb'], changelog: '1.0.0', tags: ['v1.0.0']}},
    ) do |output, _status|
      _(output).must_include 'url names v9.9.9, which is not a tag in the repository'
    end
  end
end

# Reachability finds the candidates and the tree decides which of them matter, a
# tag naming a commit outside the branch being harmless where it names the same
# code and a shipped fault where it does not.  Each example below orphans the tag
# by a different amend, those being the three ways it happens.
describe 'the orphan check' do
  def orphaned(orphan:, tags: ['v1.0.0'])
    {
      formulae: {'thing' => formula_source('thing', tag: 'v1.0.0', install: "libexec.install 'bin', 'lib'")},
      repositories: {'thing' => {files: ['bin/thing', 'lib/Thing.rb'], changelog: '1.0.0', tags: tags, orphan: orphan}},
    }
  end

  it 'says nothing where every tag is reachable from the branch' do
    in_fixture(**agreeing(install: "libexec.install 'bin', 'lib'")) do |output, _status|
      _(output).wont_include 'orphan:'
    end
  end

  it 'reports a tag whose tree differs from the branch, that being what a pin would ship' do
    in_fixture(**orphaned(orphan: :content)) do |output, status|
      _(output).must_include "orphan: v1.0.0 names a different tree from master's 1.0.0"
      _(status).must_equal 1
    end
  end

  it 'names it bookkeeping where the tree is the same, an amended message orphaning a tag without changing a byte of code' do
    in_fixture(**orphaned(orphan: :message)) do |output, _status|
      _(output).must_include "orphan: v1.0.0 names a commit outside master, its tree being the tree of master's 1.0.0"
    end
  end

  it 'says so where the branch has no commit for the version at all' do
    in_fixture(**orphaned(orphan: :version)) do |output, _status|
      _(output).must_include 'orphan: v1.0.0 names a commit outside master, which has no commit saying 1.0.0'
    end
  end

  # A tag which is not a version has no entry to be compared against, so the
  # finding stops at where it points.
  it 'reports a tag which names no version by where it points and no further' do
    in_fixture(**orphaned(orphan: :version, tags: ['v1.0.0', 'staging'])) do |output, _status|
      _(output).must_include 'orphan: staging names a commit outside master'
      _(output).wont_include 'orphan: staging names a different tree'
    end
  end

  # The branch is asked for by name rather than of HEAD, so a repository which
  # releases from something else is told rather than guessed at.
  it 'asks the branch it is given' do
    in_fixture(**orphaned(orphan: :content), arguments: ['--branch', 'master']) do |output, _status|
      _(output).must_include "orphan: v1.0.0 names a different tree from master's 1.0.0"
    end
  end

  it 'reports a repository which has no such branch rather than answering from wherever HEAD stands' do
    in_fixture(
      formulae: {'thing' => formula_source('thing', tag: 'v1.0.0', install: "libexec.install 'bin', 'lib'")},
      repositories: {'thing' => {files: ['bin/thing', 'lib/Thing.rb'], changelog: '1.0.0', tags: ['v1.0.0'], branch: 'main'}},
    ) do |output, status|
      _(output).must_include 'orphan: no master branch, so no tag can be tested against the one released from'
      _(status).must_equal 1
    end
  end

  it 'finds that branch when told of it' do
    in_fixture(
      formulae: {'thing' => formula_source('thing', tag: 'v1.0.0', install: "libexec.install 'bin', 'lib'")},
      repositories: {'thing' => {files: ['bin/thing', 'lib/Thing.rb'], changelog: '1.0.0', tags: ['v1.0.0'], branch: 'main'}},
      arguments: ['--branch', 'main'],
    ) do |output, _status|
      _(output).wont_include 'orphan:'
    end
  end
end

# Pinning closes one hole and opens another: a version and a tag which are each
# perfectly good and name different releases.  Nothing else here compares them,
# every other check being satisfied by each alone.
describe 'the pinned version check' do
  it 'says nothing where the tag is the version' do
    in_fixture(**agreeing(install: "libexec.install 'bin', 'lib'")) do |output, _status|
      _(output).wont_include 'pin:'
    end
  end

  it 'reports a formula which pins a release other than the one it names' do
    in_fixture(
      formulae: {'thing' => formula_source('thing', version: '1.0.1', tag: 'v1.0.0', install: "libexec.install 'bin', 'lib'")},
      repositories: {'thing' => {files: ['bin/thing', 'lib/Thing.rb'], changelog: '1.0.1', tags: ['v1.0.0', 'v1.0.1']}},
    ) do |output, status|
      _(output).must_include 'pin: the formula says 1.0.1 and pins v1.0.0'
      _(status).must_equal 1
    end
  end

  # A tag which states no version cannot disagree with one.
  it 'says nothing of a tag which is not a version' do
    in_fixture(
      formulae: {'thing' => formula_source('thing', tag: 'release', install: "libexec.install 'bin', 'lib'")},
      repositories: {'thing' => {files: ['bin/thing', 'lib/Thing.rb'], changelog: '1.0.0', tags: ['release']}},
    ) do |output, _status|
      _(output).wont_include 'pin:'
    end
  end
end

# A version stated in one place is maintained; a version stated twice is a
# version which can disagree with itself, and the second place is the one nobody
# looks at.
describe 'the secondary version check' do
  def with_version_file(stated)
    {
      formulae: {'thing' => formula_source('thing', tag: 'v1.0.0', install: "libexec.install 'bin', 'lib'")},
      repositories: {'thing' => {files: ['bin/thing', 'lib/Thing/VERSION.rb'], changelog: '1.0.0', tags: ['v1.0.0'], version_file: ['lib/Thing/VERSION.rb', stated]}},
    }
  end

  it 'says nothing where every place states the same version' do
    in_fixture(**with_version_file('1.0.0')) do |output, _status|
      _(output).wont_match(/version: lib/)
    end
  end

  it 'reports a VERSION.rb which has been left behind' do
    in_fixture(**with_version_file('0.9.0')) do |output, status|
      _(output).must_include 'version: lib/Thing/VERSION.rb says 0.9.0 and the formula says 1.0.0'
      _(status).must_equal 1
    end
  end

  it 'reports a script header which has been left behind' do
    in_fixture(
      formulae: {'thing' => formula_source('thing', tag: 'v1.0.0', install: "libexec.install 'bin', 'lib'")},
      repositories: {'thing' => {files: ['lib/Thing.rb'], changelog: '1.0.0', tags: ['v1.0.0'], header_version: '0.9.0'}},
    ) do |output, _status|
      _(output).must_include 'version: bin/thing says 0.9.0 and the formula says 1.0.0'
    end
  end
end

# Two fields naming the same repository, with nothing holding them together.
describe 'the homepage check' do
  it 'says nothing where the homepage and the url name one repository' do
    in_fixture(**agreeing(install: "libexec.install 'bin', 'lib'")) do |output, _status|
      _(output).wont_include 'homepage:'
    end
  end

  it 'reports a homepage naming another repository' do
    in_fixture(
      formulae: {'thing' => formula_source('thing', tag: 'v1.0.0', homepage: 'something-else', install: "libexec.install 'bin', 'lib'")},
      repositories: {'thing' => {files: ['bin/thing', 'lib/Thing.rb'], changelog: '1.0.0', tags: ['v1.0.0']}},
    ) do |output, status|
      _(output).must_include 'homepage: names something-else and the url names thing'
      _(status).must_equal 1
    end
  end
end

# None of these is found by installing the formula, which is why they went
# unnoticed for as long as they did.
describe 'the standard files check' do
  def without(**standard)
    {
      formulae: {'thing' => formula_source('thing', tag: 'v1.0.0', install: "libexec.install 'bin', 'lib'")},
      repositories: {'thing' => {files: ['bin/thing', 'lib/Thing.rb'], changelog: '1.0.0', tags: ['v1.0.0'], standard: standard}},
    }
  end

  it 'says nothing where every standard file is there' do
    in_fixture(**agreeing(install: "libexec.install 'bin', 'lib'")) do |output, status|
      _(output).wont_match(/README\.md:|LICENSE:|CHANGELOG:|\.gitignore:|license:/)
      _(status).must_equal 0
    end
  end

  it 'reports a repository with no README' do
    in_fixture(**without(readme: false)) do |output, _status|
      _(output).must_include 'README.md: none'
    end
  end

  it 'reports a README which names no licence' do
    in_fixture(
      formulae: {'thing' => formula_source('thing', tag: 'v1.0.0', install: "libexec.install 'bin', 'lib'")},
      repositories: {'thing' => {files: ['bin/thing', 'lib/Thing.rb'], changelog: '1.0.0', tags: ['v1.0.0'], readme_body: "# thing\n\nWhatever it does.\n"}},
    ) do |output, _status|
      _(output).must_include 'README.md: no License section'
    end
  end

  it 'reports a repository with no LICENSE' do
    in_fixture(**without(licence: false)) do |output, _status|
      _(output).must_include 'LICENSE: none'
    end
  end

  it 'reports a repository with no CHANGELOG' do
    in_fixture(
      formulae: {'thing' => formula_source('thing', tag: 'v1.0.0', install: "libexec.install 'bin', 'lib'")},
      repositories: {'thing' => {files: ['bin/thing', 'lib/Thing.rb'], tags: ['v1.0.0']}},
    ) do |output, _status|
      _(output).must_include 'CHANGELOG: none'
    end
  end

  it 'reports a formula declaring no licence' do
    in_fixture(
      formulae: {'thing' => formula_source('thing', tag: 'v1.0.0', license: nil, install: "libexec.install 'bin', 'lib'")},
      repositories: {'thing' => {files: ['bin/thing', 'lib/Thing.rb'], changelog: '1.0.0', tags: ['v1.0.0']}},
    ) do |output, _status|
      _(output).must_include 'license: the formula declares none'
    end
  end

  it 'reports a .gitignore short of the template, startor having carried a one-line one' do
    in_fixture(**without(gitignore: 1)) do |output, _status|
      _(output).must_include '.gitignore: 1 lines, the template being 47'
    end
  end

  it 'reports a repository with no .gitignore at all, as gem-homepage had' do
    in_fixture(**without(gitignore: false)) do |output, _status|
      _(output).must_include '.gitignore: none'
    end
  end
end

# The tap states its formulae twice over, and a formula added or renamed leaves
# both lists saying what the tap no longer holds.
describe "the tap's own README" do
  it 'says nothing where both lists name every formula' do
    in_fixture(**agreeing(install: "libexec.install 'bin', 'lib'")) do |output, _status|
      _(output).wont_include "the tap's own README"
    end
  end

  it 'reports a formula the install list does not name' do
    in_fixture(**agreeing(install: "libexec.install 'bin', 'lib'"), tap_readme: {installed: []}) do |output, status|
      _(output).must_include 'the install list does not name thing'
      _(status).must_equal 1
    end
  end

  it 'reports a formula the sources list does not name' do
    in_fixture(**agreeing(install: "libexec.install 'bin', 'lib'"), tap_readme: {sourced: []}) do |output, _status|
      _(output).must_include 'the sources list does not name thing'
    end
  end

  it 'reports a name listed which is no formula, a formula renamed leaving the old name behind' do
    in_fixture(**agreeing(install: "libexec.install 'bin', 'lib'"), tap_readme: {installed: ['thing', 'gone']}) do |output, _status|
      _(output).must_include 'the install list names gone, which is no formula here'
    end
  end

  it 'says nothing of a tap holding no formulae, there being nothing for a README to name' do
    Dir.mktmpdir do |root|
      output, status = audit('--formulae', root, '--repositories', root)
      _(output).wont_include "the tap's own README"
      _(status).must_equal 0
    end
  end
end

# A pinned url is fetched from origin, so origin is the only place the question
# can be asked.  Everything else here reads the clone, which can be in perfect
# order while origin serves something else — the state fifty-eight tags across
# eight repositories were in on 20260822, none of them visible from a clone.
describe 'the origin check' do
  # A bare repository beside the working one, pushed to and then interfered with,
  # so that origin and the clone can be made to disagree in each of the ways they
  # have actually disagreed.
  def with_origin(spoil: nil, arguments: ['--origin'])
    Dir.mktmpdir do |root|
      tap = File.join(root, 'tap')
      repositories = File.join(root, 'repositories')
      FileUtils.mkdir_p([tap, repositories])
      File.write(File.join(tap, 'thing.rb'), formula_source('thing', tag: 'v1.0.0', install: "libexec.install 'bin', 'lib'"))
      write_tap_readme(tap, ['thing'])
      make_repository(repositories, 'thing', files: ['bin/thing', 'lib/Thing.rb'], changelog: '1.0.0', tags: ['v1.0.0'])
      directory = File.join(repositories, 'thing')
      origin = File.join(root, 'origin.git')
      git(directory, 'init', '--bare', '--quiet', origin)
      git(directory, 'remote', 'add', 'origin', origin)
      git(directory, 'push', '--quiet', 'origin', 'master', 'v1.0.0') unless spoil == :untagged
      git(directory, 'push', '--quiet', 'origin', 'master') if spoil == :untagged
      spoil_origin(directory, origin, spoil)
      yield(*audit('--formulae', tap, '--repositories', repositories, '--search-path', '', *arguments))
    end
  end

  # :moved   the clone retags and does not push, which every tag -f leaves behind
  # :orphan  the branch is rewritten and force-pushed, the tag left where it was
  def spoil_origin(directory, _origin, spoil)
    case spoil
    when :moved
      File.write(File.join(directory, 'again'), 'x')
      git(directory, 'add', '.')
      git(directory, '-c', 'user.email=s@e', '-c', 'user.name=s', 'commit', '--quiet', '-m', '1.0.0: whatever it was.')
      git(directory, 'tag', '--force', 'v1.0.0')
    when :orphan
      File.write(File.join(directory, 'again'), 'x')
      git(directory, 'add', '.')
      git(directory, '-c', 'user.email=s@e', '-c', 'user.name=s', 'commit', '--quiet', '--amend', '-m', '1.0.0: whatever it was.')
      git(directory, 'push', '--quiet', '--force', 'origin', 'master')
    end
  end

  it 'says nothing where origin serves the release the pin names' do
    with_origin do |output, _status|
      _(output).wont_include 'origin:'
    end
  end

  it 'is not asked for unless it is asked for, being the one thing here which touches the network' do
    with_origin(spoil: :untagged, arguments: []) do |output, _status|
      _(output).wont_include 'origin:'
    end
  end

  it 'reports a pin which origin has never heard of' do
    with_origin(spoil: :untagged) do |output, status|
      _(output).must_include 'origin: has no v1.0.0, so the pin resolves in this clone and nowhere else'
      _(status).must_equal 1
    end
  end

  it 'reports a tag which origin and the clone disagree about, a retag not pushed leaving exactly this' do
    with_origin(spoil: :moved) do |output, status|
      _(output).must_match(/origin: v1\.0\.0 names \h+ and this clone's names \h+/)
      _(status).must_equal 1
    end
  end

  it 'reports a tag outside the branch origin releases from, which is what a pinned build fetches' do
    with_origin(spoil: :orphan) do |output, status|
      _(output).must_include 'origin: v1.0.0 names a commit outside master there'
      _(status).must_equal 1
    end
  end
end

describe 'the directory check' do
  it 'says nothing where an install line names the directory' do
    in_fixture(**agreeing(install: "libexec.install 'bin', 'lib'")) do |output, _status|
      _(output).wont_include 'is in the repository'
    end
  end

  it 'reports a directory no install line names' do
    in_fixture(**agreeing(install: "bin.install 'bin/thing'")) do |output, status|
      _(output).must_include 'lib/ is in the repository and named by no install line'
      _(status).must_equal 1
    end
  end

  # The fault 0.0.1 was written for: a lib installed by a means which is not
  # .install is still a lib installed.
  it 'reads FileUtils.cp_r as installing the directory' do
    in_fixture(**agreeing(install: "bin.install 'bin/thing'\nFileUtils.cp_r(\"\#{pwd}/lib\", lib)")) do |output, _status|
      _(output).wont_include 'is in the repository'
    end
  end

  # skyhooks' case: four install lines commented out and nothing in their place.
  it 'does not read a commented-out install line' do
    in_fixture(**agreeing(install: "bin.install 'bin/thing'\n# libexec.install 'lib'")) do |output, _status|
      _(output).must_include 'lib/ is in the repository and named by no install line'
    end
  end

  it 'leaves test, spec and doc out of it' do
    in_fixture(
      formulae: {'thing' => formula_source('thing', tag: 'v1.0.0', install: "libexec.install 'bin', 'lib'")},
      repositories: {'thing' => {files: ['bin/thing', 'lib/Thing.rb', 'test/Thing_test.rb', 'spec/a.rb', 'doc/a.md'], changelog: '1.0.0', tags: ['v1.0.0']}},
    ) do |output, _status|
      _(output).wont_include 'test/ is in the repository'
      _(output).wont_include 'spec/ is in the repository'
      _(output).wont_include 'doc/ is in the repository'
    end
  end
end

describe 'a formula with no repository beside it' do
  it 'says so' do
    in_fixture(formulae: {'thing' => formula_source('thing')}) do |output, status|
      _(output).must_include 'no repository at'
      _(status).must_equal 1
    end
  end

  # The checks which read only the formula still have something to say, which
  # 0.2.0 first got wrong by returning upon the missing repository.
  it 'still reports an unrecognised install statement' do
    in_fixture(formulae: {'thing' => formula_source('thing', install: "Pathname.new('lib').children.each{|c| c.rename(prefix/'lib')}")}) do |output, _status|
      _(output).must_include 'unrecognised in def install'
    end
  end
end

# The check which finds an idiom nobody enumerated, this being the class of
# fault the whole tool was found to have: a statement it cannot classify is a
# statement whose effect upon the keg it cannot know.
describe 'the unrecognised statement check' do
  it 'says nothing about the idioms the tap actually uses' do
    recognised = [
      "libexec.install 'bin', 'lib'",
      "FileUtils.cp_r(\"\#{pwd}/lib\", lib)",
      "ENV['GEM_HOME'] = (libexec/'vendor').to_s",
      "system 'gem', 'install', '--no-document', '--install-dir', libexec/'vendor',\n  *resources.map{|r| r.fetch.to_s}",
      "resources.each do |r|\n  r.fetch\nend",
      "(bin/'thing').write_env_script(\n  libexec/'bin/thing',\n  RUBYLIB: libexec/'lib',\n)",
    ]
    in_fixture(**agreeing(install: recognised.join("\n"))) do |output, _status|
      _(output).wont_include 'unrecognised'
    end
  end

  it 'reports a statement it does not know' do
    in_fixture(**agreeing(install: "libexec.install 'bin', 'lib'\nPathname.new('lib').children.each{|c| c.rename(prefix/'lib')}")) do |output, status|
      _(output).must_include "unrecognised in def install, so what it puts in the keg is unknown: Pathname.new('lib')"
      _(status).must_equal 1
    end
  end

  # A statement rejoined wrongly is reported as unrecognised, so the joiner and
  # not the whitelist is what decides the false positives.
  it 'joins a call which spans lines rather than reading each line as a statement' do
    in_fixture(**agreeing(install: "(bin/'thing').write_env_script(\n  libexec/'bin/thing',\n  RUBYLIB: libexec/'lib',\n)")) do |output, _status|
      _(output).wont_include 'unrecognised'
    end
  end
end

describe 'the same gem at more than one version' do
  it 'says nothing where every formula agrees' do
    in_fixture(
      formulae: {
        'thing' => formula_source('thing', tag: 'v1.0.0', install: STAGING, resources: {'switches.rb' => '0.10.3'}),
        'other' => formula_source('other', tag: 'v1.0.0', install: STAGING, resources: {'switches.rb' => '0.10.3'}),
      },
      repositories: {
        'thing' => {files: ['bin/thing', 'lib/Thing.rb'], changelog: '1.0.0', tags: ['v1.0.0']},
        'other' => {files: ['bin/other', 'lib/Other.rb'], changelog: '1.0.0', tags: ['v1.0.0']},
      },
    ) do |output, status|
      _(output).wont_include 'the same gem at more than one version'
      _(output).must_include '0 gems are pinned at more than one version'
      _(status).must_equal 0
    end
  end

  it 'names the versions and the formulae holding them, where both reach the gem directly' do
    in_fixture(
      formulae: {
        'thing' => formula_source('thing', tag: 'v1.0.0', install: STAGING, resources: {'switches.rb' => '0.10.3'}),
        'other' => formula_source('other', tag: 'v1.0.0', install: STAGING, resources: {'switches.rb' => '0.9.15'}),
      },
      repositories: {
        'thing' => {files: ['lib/Thing.rb'], changelog: '1.0.0', tags: ['v1.0.0'], requires: ['switches.rb']},
        'other' => {files: ['lib/Other.rb'], changelog: '1.0.0', tags: ['v1.0.0'], requires: ['switches.rb']},
      },
    ) do |output, status|
      _(output).must_include 'the same gem at more than one version'
      _(output).must_include 'switches.rb: 0.10.3 in thing; 0.9.15 in other'
      _(status).must_equal 1
    end
  end

  # git-boot names activesupport 8.1.3.1 because sym wants it, and
  # git-checkout-new-issue names 7.0.7.2 because it requires active_support
  # itself.  Separate kegs, separate load paths, no disagreement to settle.
  it 'says nothing where only one of the two reaches the gem directly' do
    in_fixture(
      formulae: {
        'thing' => formula_source('thing', tag: 'v1.0.0', install: STAGING, resources: {'switches.rb' => '0.10.3'}),
        'other' => formula_source('other', tag: 'v1.0.0', install: STAGING, resources: {'switches.rb' => '0.9.15'}),
      },
      repositories: {
        'thing' => {files: ['lib/Thing.rb'], changelog: '1.0.0', tags: ['v1.0.0'], requires: ['switches.rb']},
        'other' => {files: ['lib/Other.rb'], changelog: '1.0.0', tags: ['v1.0.0'], requires: ['something-else']},
      },
    ) do |output, _status|
      _(output).wont_include 'the same gem at more than one version'
      _(output).must_include '0 gems are pinned at more than one version'
    end
  end

  # A require does not spell its gem, so the one which is reached directly has to
  # be recognised through the path it is required by.
  it 'reads a require which does not spell its gem' do
    in_fixture(
      formulae: {
        'thing' => formula_source('thing', tag: 'v1.0.0', install: STAGING, resources: {'activesupport' => '8.1.3.1'}),
        'other' => formula_source('other', tag: 'v1.0.0', install: STAGING, resources: {'activesupport' => '7.0.7.2'}),
      },
      repositories: {
        'thing' => {files: ['lib/Thing.rb'], changelog: '1.0.0', tags: ['v1.0.0'], requires: ['active_support/core_ext/string']},
        'other' => {files: ['lib/Other.rb'], changelog: '1.0.0', tags: ['v1.0.0'], requires: ['active_support']},
      },
    ) do |output, _status|
      _(output).must_include 'activesupport: 7.0.7.2 in other; 8.1.3.1 in thing'
    end
  end

  it 'does not read a commented-out resource' do
    commented = formula_source('other', tag: 'v1.0.0', install: "libexec.install 'bin', 'lib'").sub(
      "  def install", "  # resource 'switches.rb' do\n  #   url 'https://rubygems.org/downloads/switches.rb-0.9.15.gem'\n  # end\n\n  def install")
    in_fixture(
      formulae: {
        'thing' => formula_source('thing', tag: 'v1.0.0', install: STAGING, resources: {'switches.rb' => '0.10.3'}),
        'other' => commented,
      },
      repositories: {
        'thing' => {files: ['bin/thing', 'lib/Thing.rb'], changelog: '1.0.0', tags: ['v1.0.0']},
        'other' => {files: ['bin/other', 'lib/Other.rb'], changelog: '1.0.0', tags: ['v1.0.0']},
      },
    ) do |output, _status|
      _(output).wont_include 'the same gem at more than one version'
      _(output).must_include '0 gems are pinned at more than one version'
    end
  end
end

# A directory which has been git init'd and left alone is not the same as one
# with no .git, and the difference matters: ls-files answers empty rather than
# failing, so every check reading it passes upon having found nothing.
describe 'a repository which exists but has no commits' do
  it 'says so' do
    in_fixture(**commitless) do |output, status|
      _(output).must_include 'the repository has no commits, so what it tracks and what it tags cannot be read'
      _(status).must_equal 1
    end
  end

  # The silent pass 0.3.0 was written for: lib is on the disk and installed by
  # nothing, and 0.2.0 said nothing at all about it.
  it 'reports no directory finding, rather than a passing one drawn from nothing' do
    in_fixture(**commitless) do |output, _status|
      _(output).wont_include 'is in the repository and named by no install line'
    end
  end

  # "not a tag in the repository" is true of a repository with no tags, and is
  # the wrong reason to give for it.
  it 'reports no tag finding either' do
    in_fixture(**commitless) do |output, _status|
      _(output).wont_include 'url names'
    end
  end

  # The CHANGELOG is read from the working directory rather than from git, so it
  # is the one thing still worth saying.
  it 'still compares the version against the CHANGELOG' do
    in_fixture(**commitless(version: '0.9.0')) do |output, _status|
      _(output).must_include 'the formula says 0.9.0 and the CHANGELOG says 1.0.0'
    end
  end
end

describe 'the directories it is given' do
  it 'refuses a --formulae which is not there' do
    Dir.mktmpdir do |root|
      absent = File.join(root, 'absent')
      output, status = audit('--formulae', absent, '--repositories', root)
      _(output).must_include "No such directory: #{absent}"
      _(status).must_equal 1
    end
  end

  it 'refuses a --repositories which is not there' do
    Dir.mktmpdir do |root|
      absent = File.join(root, 'absent')
      output, status = audit('--formulae', root, '--repositories', absent)
      _(output).must_include "No such directory: #{absent}"
      _(status).must_equal 1
    end
  end

  # A tap holding no formulae is not a fault, and nothing is a strange thing to
  # exit 1 upon.
  it 'reports nothing and exits 0 where the tap holds no formulae' do
    Dir.mktmpdir do |root|
      output, status = audit('--formulae', root, '--repositories', root)
      _(output).must_include '0 of 0 formulae have something to answer for'
      _(status).must_equal 0
    end
  end
end

# A resource is fetched and installed by def install or it is not installed at
# all.  Declaring one asks Homebrew for nothing by itself, which is easy to miss
# because the declaration looks like the whole of the job.
describe 'resources declared and never installed' do
  it 'says nothing where def install stages them' do
    in_fixture(**agreeing(
      install: "resources.each do |r|\n  r.fetch\nend\nlibexec.install 'bin', 'lib'",
      resources: {'switches.rb' => '0.10.3'},
    )) do |output, status|
      _(output).wont_include 'declared and installed by nothing'
      _(status).must_equal 0
    end
  end

  # moby's case: two resources declared, def install mentioning neither, so both
  # are resolved from whichever gem home the invoking ruby has.
  it 'reports resources which nothing in def install installs' do
    in_fixture(**agreeing(
      install: "libexec.install 'bin', 'lib'",
      resources: {'switches.rb' => '0.10.3', 'mechanize' => '2.9.1'},
    )) do |output, status|
      _(output).must_include '2 resources declared and installed by nothing in def install'
      _(status).must_equal 1
    end
  end

  it 'says nothing where no resource is declared at all' do
    in_fixture(**agreeing(install: "libexec.install 'bin', 'lib'")) do |output, _status|
      _(output).wont_include 'declared and installed by nothing'
    end
  end
end

# Not every formula wants depends_on 'ruby'.  The question is whether what is
# declared matches the interpreter the installed script actually names.
describe 'the interpreter check' do
  def with_shebang(shebang, depends_on:)
    {
      formulae: {'thing' => formula_source('thing', tag: 'v1.0.0', install: "libexec.install 'bin', 'lib'", depends_on: depends_on)},
      repositories: {'thing' => {files: ['lib/Thing.rb'], changelog: '1.0.0', tags: ['v1.0.0'], shebang: shebang}},
    }
  end

  it 'says nothing where a ruby script depends_on ruby' do
    in_fixture(**with_shebang('#!/usr/bin/env ruby', depends_on: ['ruby'])) do |output, status|
      _(output).wont_include 'depends_on no'
      _(status).must_equal 0
    end
  end

  it 'reports a ruby script which depends_on nothing' do
    in_fixture(**with_shebang('#!/usr/bin/env ruby', depends_on: [])) do |output, status|
      _(output).must_include 'bin/thing is a ruby script and the formula depends_on no ruby'
      _(status).must_equal 1
    end
  end

  it 'reports a python script beside a formula depending upon ruby' do
    in_fixture(**with_shebang('#!/usr/bin/env python3', depends_on: ['ruby'])) do |output, _status|
      _(output).must_include 'bin/thing is a python script and the formula depends_on no python'
    end
  end

  # gem-publish is a shell script and correctly declares nothing, sh and bash
  # being upon every machine this could install to.
  it 'asks nothing of a shell script' do
    in_fixture(**with_shebang('#!/usr/bin/env sh', depends_on: [])) do |output, status|
      _(output).wont_include 'depends_on no'
      _(status).must_equal 0
    end
  end

  it 'says nothing where there is no binary to read' do
    in_fixture(**agreeing(install: "libexec.install 'bin', 'lib'")) do |output, _status|
      _(output).wont_include 'depends_on no'
    end
  end
end

# An unqualified name resolves against homebrew/core first, so a dependency upon
# a formula in this tap has to name the tap or it finds someone else's.
describe 'a dependency upon another formula in the tap' do
  def two_formulae(dependency)
    {
      formulae: {
        'thing' => formula_source('thing', tag: 'v1.0.0', install: "libexec.install 'bin', 'lib'", depends_on: ['ruby', dependency]),
        'other' => formula_source('other', tag: 'v1.0.0', install: "libexec.install 'bin', 'lib'"),
      },
      repositories: {
        'thing' => {files: ['bin/thing', 'lib/Thing.rb'], changelog: '1.0.0', tags: ['v1.0.0']},
        'other' => {files: ['bin/other', 'lib/Other.rb'], changelog: '1.0.0', tags: ['v1.0.0']},
      },
    }
  end

  it 'reports it where the name is unqualified' do
    in_fixture(**two_formulae('other')) do |output, status|
      _(output).must_include "depends_on 'other' names a formula in this tap unqualified"
      _(status).must_equal 1
    end
  end

  it 'says nothing where the tap is named' do
    in_fixture(**two_formulae('thoran/tap/other')) do |output, status|
      _(output).wont_include 'names a formula in this tap unqualified'
      _(status).must_equal 0
    end
  end

  # A name which is not in this tap is homebrew/core's to resolve and none of
  # this tool's business.
  it 'says nothing about a dependency which is not a formula here' do
    in_fixture(**two_formulae('openssl@3')) do |output, _status|
      _(output).wont_include 'names a formula in this tap unqualified'
    end
  end
end

# The consumer half.  A formula can be correct in every other respect and still
# never be what runs, something earlier upon the search path answering to the
# name instead.  moby had this during the session which produced the tool: a gem
# shim in ~/.gem answered, and was itself broken.  It is invisible from the tap,
# so nothing else here would find it.
describe 'a copy which shadows the formula' do
  def in_path_fixture(ahead: [], behind: ['thing'], brew_on_path: true)
    Dir.mktmpdir do |root|
      tap = File.join(root, 'tap')
      repositories = File.join(root, 'repositories')
      early = File.join(root, 'early')
      late = File.join(root, 'late')
      brew_bin = File.join(root, 'prefix', 'bin')
      FileUtils.mkdir_p([tap, repositories, early, late, brew_bin])
      ahead.each{|n| FileUtils.touch(File.join(early, n))}
      behind.each{|n| FileUtils.touch(File.join(brew_bin, n))}
      File.write(File.join(tap, 'thing.rb'), formula_source('thing', tag: 'v1.0.0', install: "libexec.install 'bin', 'lib'"))
      write_tap_readme(tap, ['thing'])
      make_repository(repositories, 'thing', files: ['bin/thing', 'lib/Thing.rb'], changelog: '1.0.0', tags: ['v1.0.0'])
      search = brew_on_path ? [early, brew_bin, late] : [early, late]
      yield(*audit('--formulae', tap, '--repositories', repositories,
        '--search-path', search.join(File::PATH_SEPARATOR), '--brew-prefix', File.join(root, 'prefix')))
    end
  end

  it 'reports a copy searched before Homebrew bin' do
    in_path_fixture(ahead: ['thing']) do |output, status|
      _(output).must_match(%r{/early/thing is searched before .*/prefix/bin})
      _(output).must_include %q{the formula's own copy never runs}
      _(status).must_equal 1
    end
  end

  it 'says nothing where nothing is ahead of it' do
    in_path_fixture(ahead: []) do |output, status|
      _(output).wont_include 'is searched before'
      _(status).must_equal 0
    end
  end

  # A copy after Homebrew's bin is not a shadow: the formula answers first.
  it 'says nothing about a copy searched after Homebrew bin' do
    in_path_fixture(ahead: ['something-else']) do |output, status|
      _(output).wont_include 'is searched before'
      _(status).must_equal 0
    end
  end

  # Nothing can shadow a bin which is not searched at all, and reporting the
  # first directory on the path as a shadow would be nonsense.
  it 'says nothing where Homebrew bin is not upon the search path' do
    in_path_fixture(ahead: ['thing'], brew_on_path: false) do |output, status|
      _(output).wont_include 'is searched before'
      _(status).must_equal 0
    end
  end
end
