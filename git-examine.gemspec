Gem::Specification.new do |s|
  s.name = 'git-examine'
  s.version = '0.1'
  s.licenses = ['BSD-3-Clause']
  s.date = '2014-04-29'
  s.author = 'Tanaka Akira'
  s.email = 'akr@fsij.org'
  s.required_ruby_version = '>= 2.1'
  s.files = %w[
    LICENSE
    README.md
    bin/git-examine
    lib/git-examine.rb
    lib/git-examine/git.rb
    lib/git-examine/main.rb
  ]
  s.test_files = %w[
  ]
  s.homepage = 'https://github.com/akr/git-examine'
  s.require_path = 'lib'
  s.executables << 'git-examine'
  s.summary = 'an interactive wrapper for "annotate" and "diff" of git'
  s.description = <<'End'
git-examine is an interactive wrapper for "annotate" and "diff" of git.

git-examine enables you to browse annotated sources and diffs interactively.
End
end
