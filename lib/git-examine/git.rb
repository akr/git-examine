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

    f_prev_rev = nil
    r_prev_rev = nil
    0.upto(forward_data.length-1) {|ln|
      f_rev, f_author_time, f_author_name, f_content_line, f_filename, f_original_file_line_number = forward_data[ln]
      r_rev, r_author_time, r_author_name, r_content_line, r_filename, r_original_file_line_number = reverse_data[ln]

      ln += 1
      result << %{<a name="#{h ln.to_s}"></a>}

      f_formatted_author_time = f_prev_rev == f_rev ? ' ' * 10 : f_author_time
      f_formatted_author_name = "%-#{forward_author_name_width}s" % f_author_name
      f_commit_url = "/diff-parents/#{f_rev}\##{u(f_rev+"/"+f_filename.to_s+":"+f_original_file_line_number.to_s)}"

      r_formatted_author_time = r_prev_rev == r_rev ? ' ' * 10 : r_author_time
      r_commit_url = "/diff-children/#{r_rev}\##{u(r_rev+"/"+r_filename.to_s+":"+r_original_file_line_number.to_s)}"

      f_prev_rev = f_rev
      r_prev_rev = r_rev

      result << %{<a href="#{h f_commit_url}">#{h f_formatted_author_time}</a> }
      result << %{<a href="#{h r_commit_url}">#{h r_formatted_author_time}</a> }
      result << %{#{h f_formatted_author_name} }
      result << %{#{h f_content_line}\n}
    }

    result << '</pre>'

    result
  end

  def format_commit(list)
    target_rev = list[0]
    log_out, log_status = Open3.capture2({'LC_ALL'=>'C'},
	'git', "--git-dir=#{@topdir.to_s}/.git", "--work-tree=#{@topdir.to_s}", 'log', '--name-status', '--date=iso', '-1', '--parents', target_rev)
    log_out.force_encoding('locale').scrub!
    if !log_status.success?
      raise "git log failed."
    end

    if /^commit ([0-9a-f]+)(.*)\n/ !~ log_out
      raise "git log doesn't produce 'commit' line."
    end
    commit_rev = $1
    parent_revs = $2.strip.split(/\s+/)

    result = ""
    result << "<ul>\n"
    result << "<li>commit_hash=#{h target_rev}</li>\n"
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

    if parent_revs.empty?
      result << "no diffs since no parents: #{target_rev}"
    else
      parent_revs.each {|parent_rev|
        result << format_diff(parent_rev, commit_rev)
      }
    end

    result
  end

  def format_diff_children(list)
    target_rev = list[0]

    log_out, log_status = Open3.capture2({'LC_ALL'=>'C'},
	'git', "--git-dir=#{@topdir.to_s}/.git", "--work-tree=#{@topdir.to_s}", 'log', '--pretty=format:%H %P')
    log_out.force_encoding('locale').scrub!
    if !log_status.success?
      raise "git log failed."
    end

    children = {}
    log_out.each_line {|line|
      commit_hash, *parent_revs = line.strip.split(/\s+/)
      parent_revs.each {|parent_rev|
        children[parent_rev] ||= []
        children[parent_rev] << commit_hash
      }
    }

    unless children[target_rev]
      return "no diffs since no children: #{target_rev}"
    end

    result = String.new

    children[target_rev].each {|child_rev|
      log_out, log_status = Open3.capture2({'LC_ALL'=>'C'},
          'git', "--git-dir=#{@topdir.to_s}/.git", "--work-tree=#{@topdir.to_s}", 'log', '--name-status', '--date=iso', '-1', child_rev)
      log_out.force_encoding('locale').scrub!
      if !log_status.success?
        raise "git log failed."
      end

      result = '<pre>'
      log_out.each_line {|line|
        result << "#{h line.chomp}\n"
      }
      result << '</pre>'

      result << format_diff(target_rev, child_rev)
    }

    result
  end

  def format_diff(rev1, rev2)
    result = String.new
    diff_out, diff_status = Open3.capture2({'LC_ALL'=>'C'},
        'git', "--git-dir=#{@topdir.to_s}/.git", "--work-tree=#{@topdir.to_s}", 'diff', rev1, rev2)
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
        rev1_url = "/file/#{rev1}/#{filename1}\##{ln_cur1}"
        result << %{<a name="#{h(u(rev1.to_s+"/"+filename1+":"+ln_cur1.to_s))}"></a>}
        result << %{<a href="#{h rev1_url}"> -</a>}
        result << (h content_line) << "\n"
      when :add
        line, content_line, ln_cur2 = rest
        content_line = content_line.chomp.expand_tab
        rev2_url = "/file/#{rev2}/#{filename2}\##{ln_cur2}"
        result << %{<a name="#{h(u(rev2.to_s+"/"+filename2+":"+ln_cur2.to_s))}"></a>}
        result << %{<a href="#{h rev2_url}"> +</a>}
        result << (h content_line) << "\n"
      when :com
        line, content_line, ln_cur1, ln_cur2 = rest
        content_line = content_line.chomp.expand_tab
        rev1_url = "/file/#{rev1}/#{filename1}\##{ln_cur1}"
        rev2_url = "/file/#{rev2}/#{filename2}\##{ln_cur2}"
        result << %{<a name="#{h(u(rev1.to_s+"/"+filename1+":"+ln_cur1.to_s))}"></a>}
        result << %{<a name="#{h(u(rev2.to_s+"/"+filename2+":"+ln_cur2.to_s))}"></a>}
        result << %{<a href="#{h rev1_url}"> </a>}
        result << %{<a href="#{h rev2_url}"> </a>}
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
