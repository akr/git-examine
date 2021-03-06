include ERB::Util # "h" and "u" for escaping as HTML and URL.

class String
  # expand TABs destructively.
  # TAB width is assumed as 8.
  def expand_tab!
    self.sub!(/\A\t+/) { ' ' * ($&.length * 8) }
    nil
  end

  # returns a string which TABs are expanded.
  # TAB width is assumed as 8.
  def expand_tab
    result = dup
    result.expand_tab!
    result
  end
end


def shell_escape_word(word)
  if %r{\A[,-./0-9:=@A-Z_a-z~]+\z} =~ word
    word
  else
    "'" + word.gsub(/'/, "'\\''") + "'"
  end
end

def shell_escape_command(command)
  if command[0].is_a? Hash
    env = command[0]
    command = command[1..-1]
  else
    env = nil
  end
  ary = []
  if env
    env.each {|k,v|
      ary << "#{shell_escape_word k}=#{shell_escape_word v}"
    }
  end
  command.each {|word|
    ary << shell_escape_word(word)
  }
  ary.join(' ')
end

def scan_udiff(string)
  ln_cur1 = 0
  ln_cur2 = 0
  ln_num1 = 0
  ln_num2 = 0
  string.each_line {|line|
    line.force_encoding('locale').scrub!
    case line
    when /\A---\s+(\S+)/
      yield :filename1, line, $1
    when /\A\+\+\+\s+(\S+)/
      yield :filename2, line, $1
    when /\A@@ -(\d+),(\d+) \+(\d+),(\d+) @@/
      ln_cur1 = $1.to_i
      ln_num1 = $2.to_i
      ln_cur2 = $3.to_i
      ln_num2 = $4.to_i
      yield :hunk_header, line, ln_cur1, ln_num1, ln_cur2, ln_num2
    else
      if /\A-/ =~ line && 0 < ln_num1
        content_line = $'
        yield :del, line, content_line, ln_cur1
        ln_cur1 += 1
        ln_num1 -= 1
      elsif /\A\+/ =~ line && 0 < ln_num2
        content_line = $'
        yield :add, line, content_line, ln_cur2
        ln_cur2 += 1
        ln_num2 -= 1
      elsif /\A / =~ line && 0 < ln_num1 && 0 < ln_num2
        content_line = $'
        yield :com, line, content_line, ln_cur1, ln_cur2
        ln_cur1 += 1
        ln_cur2 += 1
        ln_num1 -= 1
        ln_num2 -= 1
      else
        yield :other, line
      end
    end
  }
end

NullLogSink = Object.new
def NullLogSink.<<(s)
end
NullLog = WEBrick::BasicLog.new(NullLogSink)

class Server
  def initialize(repo)
    @repo = repo
    @httpd = WEBrick::HTTPServer.new(
     :BindAddress => '127.0.0.1',
     :Port => 0,
     :AccessLog => NullLog,
     :Logger => NullLog)
    @httpd.mount_proc("/") {|req, res|
      handle_request0(repo, req, res)
    }
    trap(:INT){ @httpd.shutdown }
    addr = @httpd.listeners[0].connect_address
    @http_root = "http://#{addr.ip_address}:#{addr.ip_port}"
    @th = Thread.new { @httpd.start }
  end

  def stop
    @httpd.shutdown
    @th.join
  end

  def annotate_url(filetype, commit_hash, relpath)
    names = relpath.split(/\/+/)
    raise "relpath contains .." if names.include?('..')
    names.delete('.')
    reluri = names.map {|n| '/' + u(n) }.join
    "#{@http_root}/#{filetype}/#{commit_hash}#{reluri}"
  end

  def handle_request0(repo, req, res)
    begin
      handle_request(repo, req, res)
    rescue Exception
      res.content_type = 'text/html'
      result = '<pre>'
      result << "#{h $!.message} (#{h $!.class})\n"
      $!.backtrace.each {|b|
        result << "#{h b}\n"
      }
      result << "</pre>"
      res.body = result
    end
  end

  def handle_request(repo, req, res)
    res.content_type = 'text/html'
    uri = req.request_uri
    list = uri.path.scan(%r{[^/]+}).map {|s| CGI.unescape(s) }
    assoc = uri.query ? URI.decode_www_form(uri.query) : []
    case list[0]
    when 'dir'
      res.body = repo.format_dir list[1..-1], assoc
    when 'file'
      res.body = repo.format_file list[1..-1], assoc
    when 'commit', 'diff-parents'
      res.body = repo.format_commit list[1..-1], assoc
    when 'diff-children'
      res.body = repo.format_diff_children list[1..-1], assoc
    when 'log'
      res.body = repo.format_log list[1..-1], assoc
    else
      raise "unexpected command"
    end
  end
end

def find_git_repository(relpath, d, commit_hash)
  relpath = relpath.to_s
  if commit_hash
    command = ['git', "--git-dir=#{d.to_s}/.git", "--work-tree=#{d.to_s}", 'log', '--pretty=format:%H', '-1', commit_hash, "--", "#{d.to_s}/#{relpath}"]
  else
    command = ['git', "--git-dir=#{d.to_s}/.git", "--work-tree=#{d.to_s}", 'log', '--pretty=format:%H', '-1', "--", "#{d.to_s}/#{relpath}"]
  end
  commit_hash, status = Open3.capture2(*command)
  if !status.success?
    raise "git log failed"
  end
  return GITRepo.new(d), relpath, commit_hash
end

def parse_arguments(argv)
  # process options
  if argv.length == 1
    commit_hash = nil
    filename = argv[0]
  else
    commit_hash = argv[0]
    filename = argv[1]
  end
  [filename, commit_hash]
end

def setup_repository(filename, commit_hash)
  filename ||= '.'
  f = Pathname(filename).realpath
  [*f.ascend.to_a, Pathname('.')].each {|d|
    if (d+".git").exist?
      relpath = f.relative_path_from(d)
      return find_git_repository(relpath, d, commit_hash)
    end
  }
  raise "cannot find a repository"
end

def run_browser(url)
  #ret = system "xterm", "-e", "w3m", url
  ret = system "w3m", url
  if ret != true
    raise "w3m not found"
  end
end

def main(argv)
  filename, commit_hash = parse_arguments(argv)
  repo, relpath, commit_hash = setup_repository filename, commit_hash
  filetype = repo.file_type(commit_hash, relpath)
  server = Server.new(repo)
  run_browser server.annotate_url(filetype, commit_hash, relpath)
  exit(true)
end
