class GITRepo
  def initialize(topdir)
    @topdir = topdir
  end

  def file_type(commit_hash, relpath)
    if relpath == '.'
      'dir'
    else
      command = ['git', "--git-dir=#{@topdir}/.git", "--work-tree=#{@topdir}", 'ls-tree', '--full-tree', '-z', commit_hash, relpath]
      out, status = Open3.capture2(*command)
      case out
      when /\A\d+ blob /
        'file'
      when /\A\d+ tree /
        'dir'
      else
        raise "unexpected result in git ls-tree"
      end
    end
  end

  def format_log(list)
    commit_hash = list[0]
    relpath_list = list[1..-1]
    relpath = relpath_list.empty? ? '.' : relpath_list.map {|n| n + '/' }.join
    command = [{'LC_ALL'=>'C'}, 'git', "--git-dir=#{@topdir}/.git", "--work-tree=#{@topdir}", 'log', '-z', relpath]
    out, status = Open3.capture2(*command)
    result = ""
    result << "<ul>\n"
    result << "<li>commit_hash=#{h commit_hash}</li>\n"
    result << "<li>relpath=#{h relpath}</li>\n"
    result << "</ul>\n"
    out.each_line("\0") {|commit|
      commit.chomp!("\0")
      result << "<pre>"
      commit.each_line {|line|
        case line
        when /\Acommit (\S+)(.*)\n/
          this_commit_hash, rest = $1, $2
          href = ['commit', this_commit_hash].map {|n| u(n) }.join('/')
          result << %Q{commit <a name="#{this_commit_hash}" href="/#{href}">#{h(this_commit_hash)}</a>#{h(rest)}\n}
        else
          result << h(line)
        end
      }
      result << "</pre>\n"
    }
    result
  end

  def format_dir(list)
    commit_hash = list[0]
    relpath_list = list[1..-1]
    relpath = relpath_list.empty? ? '.' : relpath_list.map {|n| n + '/' }.join
    command = [{'LC_ALL'=>'C'}, 'git', "--git-dir=#{@topdir}/.git", "--work-tree=#{@topdir}", 'ls-tree', '--full-tree', '-z', commit_hash, relpath]
    out, status = Open3.capture2(*command)
    result = ""
    result << "<ul>\n"
    result << "<li>commit_hash=#{h commit_hash}</li>\n"
    result << "<li>relpath=#{h relpath}</li>\n"
    href = ['log', commit_hash, *relpath_list].map {|n| u(n) }.join('/') + '#' + commit_hash
    result << %Q{<li><a href="/#{h href}">log</a></li>\n}
    result << "</ul>\n"
    result << "<pre>"
    out.each_line("\0") {|line|
      unless /\A(\S+) (\S+) (\S+)\t([^\0]*)\0\z/ =~ line
        raise "unexpected line in git-ls-tree: #{line.inspect}"
      end
      mode = $1
      filetype = $2
      obj = $3
      filename = $4
      case filetype
      when 'blob'
        href = ['file', commit_hash, *filename.split(/\//)]
        href.delete('.')
        href.map! {|n| u(n) }
        result << %Q{#{h filetype} <a href="/#{href.join('/')}">#{h filename}</a>\n}
      when 'tree'
        href = ['dir', commit_hash, *filename.split(/\//)]
        href.delete('.')
        href.map! {|n| u(n) }
        result << %Q{#{h filetype} <a href="/#{href.join('/')}">#{h filename}</a>\n}
      else
        result << %Q{#{h filetype} #{h filename}\n}
      end
    }
    result << "</pre>\n"
    result
  end

  def parse_git_blame_porcelain(command)
    out, status = Open3.capture2(*command)
    out.force_encoding('locale').scrub!
    if !status.success?
      raise "git blame failed: #{command.join(" ")}"
    end

    header_hash = {}
    prev_header = {}
    block = []
    out.each_line {|line|
      line.force_encoding('locale').scrub!
      if /\A\t/ !~ line
        block << line
      else
        content_line = line.sub(/\A\t/, '')
        commit_hash, original_file_line_number, final_file_line_number, numlines = block.shift.split(/\s+/)
        if !header_hash[commit_hash]
          header = {}
          block.each {|header_line|
            if / / =~ header_line.chomp
              header[$`] = $'
            end
          }
          header_hash[commit_hash] = header
        end
        header = header_hash[commit_hash]
        yield commit_hash, original_file_line_number, final_file_line_number, numlines, header, content_line
        block = []
      end
    }
  end

  def git_blame_forward_each(topdir, relpath, commit_hash, &b)
    command = ['git', "--git-dir=#{topdir}/.git", "--work-tree=#{topdir}", 'blame', '--porcelain', commit_hash, '--', "#{topdir}/#{relpath}"]
    parse_git_blame_porcelain(command, &b)
  end

  def git_blame_reverse_each(topdir, relpath, commit_hash, &b)
    command = ['git', "--git-dir=#{topdir}/.git", "--work-tree=#{topdir}", 'blame', '--porcelain', '--reverse', commit_hash, '--', "#{topdir}/#{relpath}"]
    parse_git_blame_porcelain(command, &b)
  end

  def format_file(list)
    commit_hash = list[0]
    relpath = list[1..-1].join('/')

    result = '<pre>'

    forward_data = []
    forward_author_name_width = 0
    git_blame_forward_each(@topdir.to_s, relpath, commit_hash) {|commit_hash, original_file_line_number, final_file_line_number, numlines, header, content_line|
      author_time = Time.at(header['author-time'].to_i).strftime("%Y-%m-%d")
      author_name = header['author'] || 'no author'
      content_line = content_line.chomp.expand_tab
      forward_author_name_width = author_name.length if forward_author_name_width < author_name.length
      forward_data << [commit_hash, author_time, author_name, content_line, header['filename'], original_file_line_number]
    }

    reverse_data = []
    git_blame_reverse_each(@topdir.to_s, relpath, commit_hash) {|commit_hash, original_file_line_number, final_file_line_number, numlines, header, content_line|
      author_time = Time.at(header['author-time'].to_i).strftime("%Y-%m-%d")
      author_name = header['author']
      content_line = content_line.chomp.expand_tab
      reverse_data << [commit_hash, author_time, author_name, content_line, header['filename'], original_file_line_number]
    }

    if forward_data.length != reverse_data.length
      raise "different length with forward and reverse blame: forward=#{forward_data.length} != reverse=#{reverse_data.length}"
    end

    f_prev_commit = nil
    r_prev_commit = nil
    0.upto(forward_data.length-1) {|ln|
      f_commit, f_author_time, f_author_name, f_content_line, f_filename, f_original_file_line_number = forward_data[ln]
      r_commit, r_author_time, r_author_name, r_content_line, r_filename, r_original_file_line_number = reverse_data[ln]

      ln += 1
      result << %{<a name="#{h ln.to_s}"></a>}

      f_formatted_author_time = f_prev_commit == f_commit ? ' ' * 10 : f_author_time
      f_formatted_author_name = "%-#{forward_author_name_width}s" % f_author_name
      f_commit_url = "/diff-parents/#{f_commit}\##{u(f_commit+"/"+f_filename.to_s+":"+f_original_file_line_number.to_s)}"

      r_formatted_author_time = r_prev_commit == r_commit ? ' ' * 10 : r_author_time
      r_commit_url = "/diff-children/#{r_commit}\##{u(r_commit+"/"+r_filename.to_s+":"+r_original_file_line_number.to_s)}"

      f_prev_commit = f_commit
      r_prev_commit = r_commit

      result << %{<a href="#{h f_commit_url}">#{h f_formatted_author_time}</a> }
      result << %{<a href="#{h r_commit_url}">#{h r_formatted_author_time}</a> }
      result << %{#{h f_formatted_author_name} }
      result << %{#{h f_content_line}\n}
    }

    result << '</pre>'

    result
  end

  def format_commit(list)
    target_commit = list[0]
    log_out, log_status = Open3.capture2({'LC_ALL'=>'C'},
	'git', "--git-dir=#{@topdir.to_s}/.git", "--work-tree=#{@topdir.to_s}", 'log', '--name-status', '--date=iso', '-1', '--parents', target_commit)
    log_out.force_encoding('locale').scrub!
    if !log_status.success?
      raise "git log failed."
    end

    if /^commit ([0-9a-f]+)(.*)\n/ !~ log_out
      raise "git log doesn't produce 'commit' line."
    end
    this_commit = $1
    parent_commits = $2.strip.split(/\s+/)

    result = ""
    result << "<ul>\n"
    result << "<li>commit_hash=#{h target_commit}</li>\n"
    href = ['log', target_commit].map {|n| u(n) }.join('/') + '#' + target_commit
    result << %Q{<li><a href="/#{h href}">log</a></li>\n}
    result << "</ul>\n"

    result << '<pre>'
    log_out.each_line {|line|
      case line
      when /\Acommit (.*)\n\z/
        commits = $1
        commits = commits.scan(/\S+/).map {|c|
          href = ['commit', c].map {|n| '/' + u(n) }.join
          %Q{<a href="#{h href}">#{c}</a>}
        }.join(' ')
        result << "commit #{commits}\n"
      else
        result << "#{h line.chomp}\n"
      end
    }
    result << '</pre>'

    if parent_commits.empty?
      result << "no diffs since no parents: #{target_commit}"
    else
      parent_commits.each {|parent_commit|
        result << format_diff(parent_commit, this_commit)
      }
    end

    result
  end

  def format_diff_children(list)
    target_commit = list[0]

    log_out, log_status = Open3.capture2({'LC_ALL'=>'C'},
	'git', "--git-dir=#{@topdir.to_s}/.git", "--work-tree=#{@topdir.to_s}", 'log', '--pretty=format:%H %P')
    log_out.force_encoding('locale').scrub!
    if !log_status.success?
      raise "git log failed."
    end

    children = {}
    log_out.each_line {|line|
      commit_hash, *parent_commits = line.strip.split(/\s+/)
      parent_commits.each {|parent_commit|
        children[parent_commit] ||= []
        children[parent_commit] << commit_hash
      }
    }

    unless children[target_commit]
      return "no diffs since no children: #{target_commit}"
    end

    result = String.new

    children[target_commit].each {|child_commit|
      log_out, log_status = Open3.capture2({'LC_ALL'=>'C'},
          'git', "--git-dir=#{@topdir.to_s}/.git", "--work-tree=#{@topdir.to_s}", 'log', '--name-status', '--date=iso', '-1', child_commit)
      log_out.force_encoding('locale').scrub!
      if !log_status.success?
        raise "git log failed."
      end

      result = '<pre>'
      log_out.each_line {|line|
        result << "#{h line.chomp}\n"
      }
      result << '</pre>'

      result << format_diff(target_commit, child_commit)
    }

    result
  end

  def format_diff(commit1, commit2)
    result = String.new
    diff_out, diff_status = Open3.capture2({'LC_ALL'=>'C'},
        'git', "--git-dir=#{@topdir.to_s}/.git", "--work-tree=#{@topdir.to_s}", 'diff', commit1, commit2)
    diff_out.force_encoding('locale').scrub!
    if !diff_status.success?
      raise "git diff failed."
    end
    filename1 = filename2 = '?'
    result << '<pre>'
    scan_udiff(diff_out) {|tag, *rest|
      case tag
      when :filename1
        line, filename1 = rest
        filename1.sub!(%r{\Aa/}, '')
        result << " "
        result << (h line.chomp.expand_tab) << "\n"
      when :filename2
        line, filename2 = rest
        filename2.sub!(%r{\Ab/}, '')
        result << " "
        result << (h line.chomp.expand_tab) << "\n"
      when :hunk_header
        line, ln_cur1, ln_num1, ln_cur2, ln_num2 = rest
        result << " "
        result << (h line.chomp.expand_tab) << "\n"
      when :del
        line, content_line, ln_cur1 = rest
        content_line = content_line.chomp.expand_tab
        commit1_url = "/file/#{commit1}/#{filename1}\##{ln_cur1}"
        result << %{<a name="#{h(u(commit1.to_s+"/"+filename1+":"+ln_cur1.to_s))}"></a>}
        result << %{<a href="#{h commit1_url}"> -</a>}
        result << (h content_line) << "\n"
      when :add
        line, content_line, ln_cur2 = rest
        content_line = content_line.chomp.expand_tab
        commit2_url = "/file/#{commit2}/#{filename2}\##{ln_cur2}"
        result << %{<a name="#{h(u(commit2.to_s+"/"+filename2+":"+ln_cur2.to_s))}"></a>}
        result << %{<a href="#{h commit2_url}"> +</a>}
        result << (h content_line) << "\n"
      when :com
        line, content_line, ln_cur1, ln_cur2 = rest
        content_line = content_line.chomp.expand_tab
        commit1_url = "/file/#{commit1}/#{filename1}\##{ln_cur1}"
        commit2_url = "/file/#{commit2}/#{filename2}\##{ln_cur2}"
        result << %{<a name="#{h(u(commit1.to_s+"/"+filename1+":"+ln_cur1.to_s))}"></a>}
        result << %{<a name="#{h(u(commit2.to_s+"/"+filename2+":"+ln_cur2.to_s))}"></a>}
        result << %{<a href="#{h commit1_url}"> </a>}
        result << %{<a href="#{h commit2_url}"> </a>}
        result << (h content_line) << "\n"
      when :other
        line, = rest
        result << " "
        result << (h line.chomp.expand_tab) << "\n"
      else
        raise "unexpected udiff line tag"
      end
    }
    result << '</pre>'
    result
  end
end
