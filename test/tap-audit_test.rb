# tap-audit_test.rb

# 20260817
# 0.0.0

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

BIN = ENV['TAP_AUDIT'] || File.expand_path('../bin/tap-audit', __dir__)

# A formula with the parts each example varies and defaults for the rest, so
# that an example states the one thing it is about.
def formula_source(name, version: '1.0.0', tag: nil, install: nil, resources: {})
  url = tag ? "url 'https://github.com/thoran/#{name}.git', tag: '#{tag}'" : "url 'https://github.com/thoran/#{name}.git'"
  body = install || "bin.install 'bin/#{name}'"
  declarations = resources.collect{|gem_name, gem_version| resource_source(gem_name, gem_version)}.join
  "class #{name.capitalize} < Formula\n  version '#{version}'\n\n  #{url}\n\n#{declarations}  def install\n#{body.lines.collect{|l| '    ' + l}.join}\n  end\nend\n"
end

def resource_source(gem_name, gem_version)
  "  resource '#{gem_name}' do\n    url 'https://rubygems.org/downloads/#{gem_name}-#{gem_version}.gem'\n  end\n\n"
end

def git(directory, *arguments)
  system('git', '-C', directory, *arguments, out: File::NULL, err: File::NULL)
end

# A repository with a commit, since ls-files reports nothing before one and the
# directory check would then find nothing to miss.
def make_repository(root, name, files: [], changelog: nil, tags: [])
  directory = File.join(root, name)
  files.each{|f| FileUtils.mkdir_p(File.dirname(File.join(directory, f))); FileUtils.touch(File.join(directory, f))}
  File.write(File.join(directory, 'CHANGELOG'), "# CHANGELOG\n\n## 20260817\n\n#{changelog}: whatever it was.\n") if changelog
  git(directory, 'init', '--quiet') || (FileUtils.mkdir_p(directory) && git(directory, 'init', '--quiet'))
  git(directory, 'add', '.')
  git(directory, '-c', 'user.email=s@e', '-c', 'user.name=s', 'commit', '--quiet', '-m', 'in')
  tags.each{|t| git(directory, 'tag', t)}
end

def in_fixture(formulae: {}, repositories: {})
  Dir.mktmpdir do |root|
    tap = File.join(root, 'tap')
    repositories_directory = File.join(root, 'repositories')
    FileUtils.mkdir_p([tap, repositories_directory])
    formulae.each{|name, source| File.write(File.join(tap, "#{name}.rb"), source)}
    repositories.each{|name, options| make_repository(repositories_directory, name, **options)}
    stdout, stderr, status = Open3.capture3(BIN, '--formulae', tap, '--repositories', repositories_directory)
    yield stdout + stderr, status.exitstatus
  end
end

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
        'thing' => formula_source('thing', tag: 'v1.0.0', install: "libexec.install 'bin', 'lib'", resources: {'switches.rb' => '0.10.3'}),
        'other' => formula_source('other', tag: 'v1.0.0', install: "libexec.install 'bin', 'lib'", resources: {'switches.rb' => '0.10.3'}),
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

  it 'names the versions and the formulae holding them' do
    in_fixture(
      formulae: {
        'thing' => formula_source('thing', tag: 'v1.0.0', install: "libexec.install 'bin', 'lib'", resources: {'switches.rb' => '0.10.3'}),
        'other' => formula_source('other', tag: 'v1.0.0', install: "libexec.install 'bin', 'lib'", resources: {'switches.rb' => '0.9.15'}),
      },
      repositories: {
        'thing' => {files: ['bin/thing', 'lib/Thing.rb'], changelog: '1.0.0', tags: ['v1.0.0']},
        'other' => {files: ['bin/other', 'lib/Other.rb'], changelog: '1.0.0', tags: ['v1.0.0']},
      },
    ) do |output, status|
      _(output).must_include 'the same gem at more than one version'
      _(output).must_include 'switches.rb: 0.10.3 in thing; 0.9.15 in other'
      _(status).must_equal 1
    end
  end

  it 'does not read a commented-out resource' do
    commented = formula_source('other', tag: 'v1.0.0', install: "libexec.install 'bin', 'lib'").sub(
      "  def install", "  # resource 'switches.rb' do\n  #   url 'https://rubygems.org/downloads/switches.rb-0.9.15.gem'\n  # end\n\n  def install")
    in_fixture(
      formulae: {
        'thing' => formula_source('thing', tag: 'v1.0.0', install: "libexec.install 'bin', 'lib'", resources: {'switches.rb' => '0.10.3'}),
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
