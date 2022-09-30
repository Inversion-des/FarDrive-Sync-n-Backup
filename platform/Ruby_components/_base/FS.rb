#... require
require 'pathname'
require 'fileutils'
begin
	require 'win32/file/attributes'
rescue LoadError  # for Linux
end
require '_base/Object'
require '_base/Integer'
require '_base/Array'
require '_base/Hash_dot_notation'
# frozen_string_literal: true

PWD_MUTEX = Mutex.new

# D:\statsoft\Ruby\3.0\lib\ruby\3.0.0\pathname.rb
class Pathname
	alias :path to_s
	alias :ext extname		# .png  -extension

	def name
		@_basename ||= basename.to_s
	end

	def name_no_ext
		name.chomp ext
	end

	# -link
	def hardlink?
		return @f_hardlink if @f_hardlink != nil
		# *in case of symlink?, tarted can be a hardlink
		@f_hardlink = !symlink? && exists? && stat.nlink > 1
	end

	# *returns true even for a broken symlink
	def lexist?
		!!(lstat rescue nil)
	end
	alias :lexists? lexist?

	#- class fixes
	module Fixes
		
		# tried to cache:
		# - cleanpath — 1.7% too small
		# - chop_basename — big overhead due to params (3.47% -> 7.44%)
		
		def relative_path_from(*up)
			@_rel_path ||= {}
			return @_rel_path[up] if @_rel_path[up] != nil
			@_rel_path[up] = super
		end
		
		# -link
		def symlink?(*up)
			return @f_symlink if @f_symlink != nil
			@f_symlink = super
		end
		
		def directory?(*up)
			return @f_dir if @f_dir != nil
			@f_dir = super
		end
		alias :dir? directory?
		alias :folder? directory?
		
		def exist?(*up)
			return @f_exist if @f_exist != nil
			@f_exist = super
		end
		alias :exists? exist?
		
		def flush!(*up)
			@f_dir = nil
			@f_hardlink = nil
			@f_symlink = nil
			@f_exist = nil
		end
	end
																																							#~ Pathname/
	prepend Fixes
end


class File
	def File.arrt_flags_bits(path)
		GetFileAttributesW string_check(path).wincode
	end

	#- for class
	class << self
		#- class fixes
		module Fixes
			# File.absolute_path
			# *tests showed that this is not thread safe
			def absolute_path(*up)
				if PWD_MUTEX.owned?
					super
				else
					PWD_MUTEX.synchronize do
						super
					end
				end
			end
		end
		prepend Fixes
	end
end


class Dir
	#- for class
	class << self
		alias :pwd_ori pwd
		
		#- class fixes
		module Fixes
			def chdir(*up)
				PWD_MUTEX.synchronize do
					super
				end
			end
			# -pwd
			def pwd
				if PWD_MUTEX.owned?
					super
				else
					PWD_MUTEX.synchronize do
						super
					end
				end
			end
		end
		prepend Fixes
	end
end


# base class, adaptor for Pathname  -path -ipath
class IPath
	attr :base, :pn, :d

	# ensure IPath  -[]
	# idir = IDir[dir]
	# ifile = IFile[file]
	def self.[](str_or_inst)
		str_or_inst.is_a?(self) ? str_or_inst : self.new(str_or_inst)
	end
																																							#~ IPath\
	# IDir.new(:z_tmp_sync).create
	# base — Pathname | string | true
	def initialize(_path, base:nil)
		# *make path resolved in the current pwd (so dir will be the same even after chdir)
		# - .realpath will fail if path doesn't exist
		# - .expand_path fails if folder is like '~~_builder' (~ expand to user home dir: can't find user ~_builder (ArgumentError))

		# *fix problem that sometimes 'P:' is resolved as some deep path, while 'P:/' works fine
		_path += '/' if _path.string? && _path[-1] == ':'

		@pn =
			if _path.respond_to? :pn
				_path.pn
			elsif _path.is_a? Pathname
				_path
			else
				if _path.is_a? Symbol
					_path = _path.to_s.encode 'UTF-8'
				end
				if base&.is_a?(Pathname) || base&.is_a?(IPath)
					base+_path
				elsif base&.string?
					Pathname.new(_path == '.' ? base : base+'/'+_path)
				else
					Pathname.new(File.absolute_path _path)
				end
			end
		@d = {}   # for storing any additional data
		case base
			when true
				set_base(File.absolute_path _path)
			when nil
				:nothing
			else
				set_base base
		end
	end

	def flush!
		@path = nil
		@path_ = nil
		@pn.flush!
	end

	def method_missing(m, *args, &block)
		res = @pn.send m, *args, &block
		if res.is_a? Pathname
			# non existing folder like '12.07.22' will be detected as IFile
			cls = (res.file? || !res.dir? && !res.extname.empty?) ? IFile : IDir
			res = cls.new res, base:@base
		end
		res
	end

	def to_s
		path
	end

	def ==(other)
		other_pn = case other
			when String then IPath.new(other).pn
			when IPath then other.pn
			else other.expand_path
		end
		@pn == other_pn
	end

	def set_base(base)
		@base = base
		self
	end
																																							#~ IPath
	# relative if possible
	def path
		_ = @path
		return _ if _
		@path = relative_path_from(@base || Dir.pwd).path
		# *sometimes we need to see '.' as path
		# res = super if res == '.'
		@path
	# if different prefix — show full path
	rescue ArgumentError
		abs_path
	end

	# *needed for faster: path_+fname instead of "=path/=fname"
	def path_
		@path_ ||= path == '.' ? '' : path+'/'
	end

	def abs_path
		@pn.path
	end

	# -link
	# dir.link.relative?
	# < PN
	def link
		@pn.readlink
	end
																																							#~ IPath
	# -symlink -link
	# *if src doesn't exist yet — link will be broken
	# *src can be abs or relative
	# res = symlink_to src, lmtime:dir_up_d.mtime, can_fail:yes
	# if res.failed
	#		res.retry.()
	def symlink_to(src, lmtime:nil, can_fail:false)
		res = {}
		msg = "(symlink_to for '#{self}') failed: src doesn't exist yet: #{src}"
		target = File.absolute_path?(src) ? IDir[src] : parent/src
		operation = -> do
			target.flush!
			raise FS::KnownError, msg unless target.exists?
			delete if lexist?
			parent.in do
				# inside: File.symlink ori_path, link_name
				make_symlink src
				#. *broken link was a file, now it is a dir
				flush!
				if lmtime
					lmtime = Time.at(lmtime) if lmtime.numeric?
					self.lmtime = lmtime
				end
			end
		end
		if target.exists?
			operation.()
			res.ok = true
		else
			if can_fail
				res.failed = true
				res.retry = operation
			else
				raise FS::KnownError, msg
			end
		end
		res
	end
																																							#~ IPath
	# -link
	def fix_link!
		src = link
		symlink_to src
	end

	#! < Pathname — може варто зберігати клас
	def relative_path_from(base)
		@pn.relative_path_from(base)
	end

	def path_first_part
		path.partition('/')[0]
	end
																																							#~ IPath
	def mtime=(mtime)
		utime mtime, mtime
	end
	def lmtime
		lstat.mtime
	end
	def lmtime=(mtime)
		File.lutime mtime, mtime, self
	rescue NotImplementedError
		# we need format like: 202104062114.01
		mtime = Time.at(mtime) if mtime.numeric?
		time_str = mtime.strftime '%Y%m%d%H%M.%S'
		# -m — change only the modification time
		# -h, --no-dereference — affect each symbolic link instead of any referenced file (useful only on systems that can change the timestamps of a symlink)
		cmd = %Q[#{FS.touch} -mh -t #{time_str} "#{abs_path}"]
		# *returns true if ok
		res = system cmd
	end

	# -attrs
	# file.attrs — ['readonly']
	# file.readonly = yes
	# file.readonly?, .hidden?
	C_attributes = %w[readonly hidden system compressed]
	def attrs(all:false)
		arr = File.attributes pn
		all ? arr : (arr & C_attributes)
	rescue Errno::ENOENT
		raise Errno::ENOENT, "(attrs) ENOENT: #{path}"
	end
																																							#~ IPath
	C_attributes.each do |m|
		# readonly?, hidden?
		get_m = m+'?'
		define_method get_m do
			File.send get_m, pn
		end

		# readonly = yes
		set_m = m+'='
		define_method set_m do |v|
			file = File.new pn
			file.send set_m, v
			file.close
		end
	end

	# file.attrs = []
	# file.attrs = ['readonly']
	def attrs=(arr)
		cur_arr = attrs
		add = arr - cur_arr
		rem = cur_arr - arr
		file = nil
		prefix = '(attrs=) '
		# *we should do 'remove' before 'add' and the first one for remove should be 'system'
		#  otherwise you can get an error — "Not resetting system file"
		if rem.delete 'system'
			rem.unshift 'system'
		end
		rem.each do |attr|
			if dir?
				cmd = case attr
					when 'readonly'
						%Q[attrib -R "#{abs_path}"]
					when 'hidden'
						%Q[attrib -H "#{abs_path}"]
					when 'system'
						%Q[attrib -S "#{abs_path}"]
					when 'compressed'
						%Q[compact /U "#{abs_path}" >nul]
				end
				if cmd
					do_cmd cmd, prefix:prefix
				end
			# file
			else
				file ||= File.new pn
				file.send attr+'=', false
			end
		end
																																							#~ IPath
		add.each do |attr|
			if dir?
				cmd = case attr
					when 'readonly'
						%Q[attrib +R "#{abs_path}"]
					when 'hidden'
						%Q[attrib +H "#{abs_path}"]
					when 'system'
						%Q[attrib +S "#{abs_path}"]
					when 'compressed'
						%Q[compact /C "#{abs_path}" >nul]
				end
				if cmd
					do_cmd cmd, prefix:prefix
				end
			# file
			else
				#. skip 'compressed' for files
				next if attr == 'compressed'
				file ||= File.new pn
				begin
					file.send attr+'=', true
				rescue Errno::ENXIO
					puts "(attrs=) failed '#{attr}=' for: #{pn}"
				end
			end
		end
		# *without this .colse the tmp file cannot be deleted (permission denied)
		file.close if file
	end

	# *IFile has .del!  -delete
	def delete
		super
		flush!
	# *file can be locked temporarily
	rescue Errno::EACCES
		# retry few times
		attempt ||= 0
		attempt += 1
		if attempt <= 5
			print ','
			sleep 0.5
			retry
		end
		raise
	end
																																							#~ IPath
	# *used for commans which exit with status 0 and return error in stdout
	private\
	def do_cmd(cmd, prefix:nil)
		err = `#{cmd}`
		# errors like:
		#	  failed: Not resetting hidden file - …
		if err != ''
			# fix problem that 'attrib' output is in CP866 with cyrillic 'і' replaced with '?'
			if cmd.start_with? 'attrib '
				err = err
					.encode('UTF-8', 'CP866')
					.gsub(/\?/, 'і')   # fix missed cyrillic 'і'
			end
			raise FS::KnownError, "#{prefix}failed: #{err}"
		end
	end

	def inspect
		# <IDir: z more files/sub folder >
		# <IFile: special/.gitignore >
		if symlink?
			link_part = "  -->  #{link}"
		elsif file? && hardlink?
			hardlink_part = ' (hardlink)'
		end
		# "<=self.class=hardlink_part: =path=link_part (=object_id) >"
		"<#{self.class}#{hardlink_part}: #{path}#{link_part} >"
	end
end
																																							#~ IPath/



# improved (-Dir )
class IDir < IPath
																																							#~ IDir\
	# ensure IDir
	# idir = IDir[dir]

	def dir?
		true
	end

	# dir = IDir.new('z-tmp').create
	# dir.create(:dir_up_d.mtime:)
	def create(mtime:nil)
		tap do |_|
			# (<!) check if the disk available
			# *needed to overcome a bug in Ruby 3.1 — https://bugs.ruby-lang.org/issues/18941
			disk = _.abs_path[0, 3]
			raise Errno::ENOENT, disk unless IDir[disk].exists?

			_.mkpath
			flush!
			if mtime
				mtime = Time.at(mtime) if mtime.numeric?
				_.mtime = mtime
			end
		end
	end

	# src_dir = dir/:src1  -/ -+
	# *returns IFile in case like: IDir.new(dir_path)/fname (type detected in method_missing)
	def +(up)
		raise "(IDir - /) error: path cannot be empty" if up.nil? || up.to_s.empty?
		# '/' in the beginning causes problem that path becomes from the root of the drive
		super up.to_s.delete_prefix('/')
	end
	alias :/ +

	# -get subdir -[
	# dir[:sub].mtime
	# @dir_local_2['.db/sets/#def_set'] << data_dir
	# *sometimes this can return IFile (depends of existance and name, see method_missing)
	def [](path)
#		ret = self
#		for name in path.split '/'
#			ret = ret/name
#		ret
		self+path
	end
																																							#~ IDir
	# -delete dir  -del dir
	def del!
		f_fso_attempt ||= false
		if f_fso_attempt
			# *workaround for folder with a very long path node deep inside
#			dir_fso = FS.win_fso.GetFolder abs_path
#			dir_fso.delete
			# object.DeleteFolder folderspec, [ force ]
			FS.win_fso.DeleteFolder abs_path
		else
			FileUtils.rmtree self.abs_path
		end
		flush!
		if exists?
			if abs_path == Dir.pwd
				raise "Cannot delete current pwd: #{abs_path}"
			else
				# *this can fail with Errno::ENOTEMPTY (Directory not empty) if there are locked files in the dir
				delete
			end
		end
	rescue Errno::ENOTEMPTY
		if !f_fso_attempt
			print '[del!: ENOTEMPTY - retry via fso]'
			f_fso_attempt = true
			retry
		end
		puts "Cannot delete dir, probably some files are locked: #{abs_path} -- skipped"
	end

	def clear!
		# *self should be resolved, not relative
		# children.each  FileUtils.rmtree ~ — this ignores standart errors
		children.each {|_| FileUtils.rm_r _ }
		raise "Cannot clear! dir: #{path}" if !empty?
		self
	rescue
		# retry few times
		attempt ||= 0
		attempt += 1
		if attempt <= 5
			# puts $!
			print ','
			# print('[enter]');$stdin.gets   # stop
			sleep 0.5
			retry
		end
		raise "Cannot clear! dir: #{path}"
	end
																																							#~ IDir
	# *slow
	def branch_files_sizes
		# was all_nodes.files instead of files_in_branch
		@branch_files_sizes ||= files_in_branch.map &:size
	end
	def flush_branch_files_sizes
		@branch_files_sizes = nil
	end

	def avrg_file_size_b
		branch_files_sizes.avrg.to_i
	end
	def median_file_size_b
		branch_files_sizes.median.to_i
	end

	# all -branch items
	# nodes = @src_dir.all_nodes
	#	  reject_by_start: [@db.dir, @tmp_dir.name, 'w.txt'] | '.db'
	# << INodes
	def all_nodes(reject_by_start:nil)
		# *glob returns [IDir/IFile], not INodes, and set_base not applied
		self
			.glob('**/*', File::FNM_DOTMATCH)
			.reject {|_| _.name == '.' }
			.then {|_| dirs_files _ }
			.tap do |_|
				if reject_by_start
					reject_by_start = [reject_by_start].flatten
					# reject by the first dir or a root file name
					_.reject! {|_| _.path_first_part.in? reject_by_start }
				end
			end
	end

	# all -branch items   -glob
	#	  reject_by_start: [@db.dir, @tmp_dir.name, 'w.txt'] | '.db'
	# << strings (rel path)
	def clear_glob(reject_by_start:nil)
		self
			.glob('**/*', File::FNM_DOTMATCH)
			.reject {|_| _.name == '.' || _ == pn }
			.map {|_| _.relative_path_from(self).path }
			.tap do |_|
				if reject_by_start
					reject_by_start = [reject_by_start].flatten
					# reject by the first dir or a root file name
					_.reject! {|_| _.partition('/')[0].in? reject_by_start }
				end
			end
	end

	# convert pn-s to INodes
	# *shuld be method of IDir because of .set_base
	# << INodes
	# *10 times slower then:
	#	dirs = @local_dir.glob("*/", File::FNM_DOTMATCH)
	#	dirs.shift 2
	def dirs_files(nodes)
		nodes
			.map do |_|
				cls = _.dir? ? IDir : IFile
				cls.new _
			end
			.each {|_| _.set_base @base || self }
			.then {|_| INodes.new _ }
	end
																																							#~ IDir

	# -children
	# ! slow
	# << INodes
	def children
		dirs_files super
	rescue Errno::ENAMETOOLONG
		res = []
		dir_fso = FS.win_fso.GetFolder abs_path
		for subdir in dir_fso.SubFolders
			res << Pathname.new(subdir.path)
		end
		for file in dir_fso.files
			res << Pathname.new(file.path)
		end
		dirs_files res
	end

	def files
		children.files
	end
	def dirs
		children.dirs
	end

	# *sum of exact file sizes, not size on disk   -total -size
	# https://stackoverflow.com/questions/55719522/how-to-get-the-total-size-of-files-in-a-directory-in-ruby
	# https://superuser.com/questions/1030800/how-can-a-files-size-on-disk-be-0-bytes-when-theres-data-in-it
	# *on Win file stats includes  blksize=nil, blocks=nil — so cannot be used
	#		like: D:\#Bkp_C\Users\Des_28.07\Des\My Documents\My Music -> C:\Users\Des\Music
	def total_size_b
		dir_d = FS.win_fso.GetFolder abs_path
		dir_d.size.to_i
	# ! fails if there is a Junction (not symlink) in the branch
	rescue WIN32OLERuntimeError
		children.then do |_|
			# *recue needed to handle Errno::ENOENT for broken links
			_.dirs.sum(&:total_size_b) + _.files.sum{|_| _.size rescue 0 }
		end
	end

	# size+cluster_overhang
	# *there is a problem that files < 700B in properties shown as size on disk: 0, but actually such files take up to 1K in file table
	# for my SMEStorage_master (7 910 Files)
	#   total_size_b —			276 040 418
	#   in dir properties —		285 265 920
	#   this returns —			292 240 098 — more real as it includes size of very small files take in the files table
	def total_size_on_disk_b
		cluster_size = 4.KB
		cluster_overhang = files_in_branch.length * (cluster_size/2)
		total_size_b + cluster_overhang
	end

	def files_in_branch
		@files_in_branch ||= self
			.glob('**/*', File::FNM_DOTMATCH)
			.reject {|_| _.directory? }
	end
	def flush_files_in_branch
		@files_in_branch = nil
	end


	# -fast -children
	# 80% faster then .children (uses 2 .globs instead of checking nodes with .dir?, doesn't create objects)
	# - full:yes — adds 1%
	# << {all_names, dirs_names, files_names} — arrays of names/paths
	def fast_children(full:false)
		path_   # cache
		all_names = Dir.glob('*', File::FNM_DOTMATCH, base:@pn.path, sort:false)
		all_names.shift if all_names[0] == '.'
		all_names.shift if all_names[0] == '..'
		dirs_names = Dir.glob('*/', File::FNM_DOTMATCH, base:@pn.path, sort:false)
		#. remove ending /
		dirs_names.each {|_| _.chop! }
		dirs_names.shift if dirs_names[0] == '.'
		dirs_names.shift if dirs_names[0] == '..'
		files_names = all_names - dirs_names
		res = {all_names:all_names, dirs_names:dirs_names, files_names:files_names}
		if full
			res.dirs_paths = dirs_names.map {|_| @path_+_ }
			res.files_paths = files_names.map {|_| @path_+_ }
			res.all_paths = res.dirs_paths + res.files_paths
		end
		res
	end
																																							#~ IDir

	# -copy dir  -<< -copy in
	# tmp_dir << 'files/main/find_new_photo' — copy dir (tmp_dir should exist, otherwise it will work as below v)
	# tmp_dir << 'files/main/find_new_photo/' — copy content of a dir (tmp_dir will be created if missed)
	# dest_dir.copy_in src, fix_links:yes
	# - first (dest) folder will be created if doesn't exist
	# - preserve symlinks
	# - junction are copied as symlinks
	# - existing files are overwritten
	def copy_in(src_dir, fix_links:false, attr:true)
		f_ends_with_slash = src_dir.to_s.end_with? '/'
		src_dir = IDir[src_dir]
		path = src_dir.abs_path
		create unless parent.exists?
		if f_ends_with_slash
			f_copy_content = true
			# *symlinks are copied (relative dir links become broken)
			# *remove_destination=false — causes Errno::EACCES (Permission denied) if the destination file is readonly
			FileUtils.copy_entry path, self, preserve=true, dereference_root=false, remove_destination=true
		else
			f_copy_content = true unless exists?
			# *existing files are overwritten
			begin
				FileUtils.cp_r path, self, preserve:true, dereference_root:false
			rescue Errno::ENAMETOOLONG
				# copy workaround
				# *src_dir.name needed bacause the content will be copied
				src_dir_fso = FS.win_fso.GetFolder path
				src_dir_fso.copy self[src_dir.name].abs_path
			end

			# *needed here because dir is created without the .create call
			flush!
		end

		if fix_links
			unless f_copy_content
				src_dir = src_dir.parent
			end
			fix_links! src_dir, self
		end

		if attr
			# copy all attributes
			base_src_dir = f_copy_content ? src_dir : src_dir.parent
			src_dir
				.glob('**/*', File::FNM_DOTMATCH)
				.reject {|_| _.name == '.' }
				.each do |src_node|
					node_copy = self[src_node.relative_path_from base_src_dir]
					next if node_copy.path == abs_path
					# file
					if src_node.file?
						# *for link it is possible that the target file is not copied yes (in this case .lexists? will return true)
						if node_copy.exists? || node_copy.lexists?
							begin
								node_copy.attrs = IFile.new(src_node).attrs
							# errors like: failed: Not resetting hidden file
							rescue FS::KnownError
								puts "(IDir - copy_in) error: file attrs copy failed for: #{node_copy.abs_path}"
							end
						else
							puts "(IDir - copy_in) error: copied file missed, probably deleted by AV (#{node_copy.abs_path})"
						end
						# *this way doesn't work — https://github.com/chef-boneyard/win32-file-attributes/issues/1
						if false
							flags_bits = File.arrt_flags_bits src_node.path
							File.set_attributes node_copy, flags_bits
						end
																																							#~ IDir - copy_in
					# dir
					else
						begin
							node_copy.attrs = IDir.new(src_node).attrs
						# *this can be caused by a folder with a very long path node deep inside
						# other possible error: Errno::ESRCH: No such process - GetFileAttributes
						rescue Errno::ENOENT
							puts "(IDir - copy_in) error: dir attrs copy failed for: #{node_copy.abs_path}"
						end
					end
				end
		end
		self
	end

	alias :<< copy_in

	# -copy content of a dir, not the dir itself  ->>
	# dest: IDir
	def copy_to(dest)
		dest = IDir.new(dest) if dest.string?
		dest.create
		# *remove_destination=false — causes Errno::EACCES (Permission denied) if the destination file is readonly
		FileUtils.copy_entry self, dest, preserve=true, dereference_root=false, remove_destination=true
		self
	end
	alias :>> copy_to

	#!. може бути що така папка вже є, треба тоді зробити щоб метод rename який є для IFile і додає цифри працював і для папки
	def rename(new_name)
		FileUtils.mv self, parent/new_name
	end


	# (>>>)
	def glob(*args)
		begin
			@pn.glob *args
		# *workaround: if .glob fails due to ENAMETOOLONG error — process this branch manually using win_fso
		#  my reported issue — https://bugs.ruby-lang.org/issues/18947
		rescue Errno::ENAMETOOLONG
			# for: glob '**/*', File::FNM_DOTMATCH
			if args[0] == '**/*'
				res = []
				dir_fso = FS.win_fso.GetFolder abs_path
				for subdir in dir_fso.SubFolders
					res << Pathname.new(subdir.path)
				end
				for file in dir_fso.files
					res << Pathname.new(file.path)
				end
				for subdir in dir_fso.SubFolders
					# (>>>)
					res += IDir[subdir.path].glob *args
				end
				res
			else
				raise
			end
		end
	end

	# dir.cd  -cd
	def cd
		Dir.chdir self
		self
	end

	# dir.in do  -cd -in
	def in(&block)
		Dir.chdir self, &block
	end

	# (>>>)
	# -link
	# fixes broken ralative symlinks
	# makes hardlinks
	# sync mtime for links
	def fix_links!(src_dir, dest_dir)
		in_dir = self
		for node in in_dir.children
			src_node = src_dir/node.relative_path_from(dest_dir)
			next if !src_node.exists?

			if node.symlink?
				if node.link.relative?
					src = in_dir/node.link
					if src.dir?
						node.fix_link!
					end
				end
				# link mtime
				node.lmtime = src_node.lmtime
			elsif node.file?
				file = node
				if src_node.hardlink?
					file.hardlink_to src_node
				end
			elsif node.dir?
				node.fix_links! src_dir, dest_dir   # (>>>)
				# is some link inside was changed — dir mtime is changed so we have to restore it
				if node.mtime != src_node.mtime
					node.mtime = src_node.mtime
				end
			end
		end
	end
end

																																							#~ IDir/

# improved File  (-file )
class IFile < IPath
																																							#~ IFile
	# ensure IFile
	# ifile = IFile[file]

	def file?
		true
	end

	def dir
		parent
	end

	# -open
	# file.open 'w'
	# file.open 'a'
	# < IFile
	def open(*args, &block)
		@file = File.open abs_path, *args, &block
		self
	end

	def method_missing(m, *args, &block)
		case m
			when :puts, :print, :flush, :close
				@file || open('w')   # open file if needed
				@file.send m, *args
			else
				# pass to IPath method_missing
				super
		end
	end

	# -same -compare
	# file.same_as(target_file, by: :checksum)
	def same_as(other_file, by:nil)
		if by == :checksum
			md5_checksum == other_file.md5_checksum
		else
			size == other_file.size && mtime == other_file.mtime
		end
	end

	# file.size(on_error:0)
	def size(on_error:nil)
		begin
			super()
		# *if file/dir is a link and target doesn't exist
		rescue Errno::ENOENT
			puts "(IFile#size) broken path: #{abs_path} (#{$!.class})"
			if on_error
				return on_error
			else
				raise
			end
		end
	end

	# *faster then .dir.path
	def dir_path
		File.dirname path
	end

	# -copy file with attributes
	# *dest can be file path or dir
	def copy_to(dest)
		if dest.is_a? IDir
			dest.create
		end
		# *preserves owner, group, and modified time. Permissions are copied regardless preserve.
		FileUtils.cp self, dest, preserve:true
		# copy attributes
		if dest.is_a? IDir
			IDir[dest][name].attrs = attrs
		else
			IFile[dest].attrs = attrs
		end
		self
	# *file can be locked temporarily
	rescue Errno::EACCES
		# retry few times
		attempt ||= 0
		attempt += 1
		if attempt <= 5
			print ','
			if dest.is_a? IDir
				(dest/name).del!
			else
				FileUtils.rm dest.to_s, force:true
			end
			retry
		end
		raise
	end
	alias :>> copy_to
																																							#~ IFile
	# dest dir should exist or such file will be created  -move -mv
	# *file is moved with attributes
	def move_to(dest)
		FileUtils.mv self, dest
	# *file can be locked temporarily
	rescue Errno::EACCES
		# retry few times
		attempt ||= 0
		attempt += 1
		if attempt <= 5
			print ','
			sleep 0.5
			retry
		end
		raise
	end
																																							#~ IFile
	# -hardlink -link
	# res = file.hardlink_to file_up_d.hard_link, can_fail:yes
	# if res.failed
	#		res.retry.()
	def hardlink_to(src, can_fail:false)
		res = {}
		src = Pathname.new src
		msg = "(hardlink_to for '#{self}') failed: src doesn't exist yet: #{src}"
		target = src.relative? ? parent/src : IFile.new(src)
		operation = -> do
			target.flush!
			raise FS::KnownError, msg unless target.exists?
			delete if exists?
			parent.in do
				# inside: File.link(src_node, link)
				make_link target
				flush!
			end
		end
		if target.exists?
			operation.()
			res.ok = true
		else
			if can_fail
				res.failed = true
				res.retry = operation
			else
				raise FS::KnownError, msg
			end
		end
		res
	end

	# -rename
	# .rename 'new_clear_name'
	# .rename('default2', ext:'jpg', add_suffix_if_needed:true)
	def rename(new_name, ext:nil, add_suffix_if_needed:nil)
		ext ||= self.ext
		ext = '.'+ext if ext[0] != '.'
		new_path = nil
		_n = 1
		suffix = ''
		catch :for_redo do
			new_path = dir/(new_name+suffix+ext)
			if File.exists? new_path
				if add_suffix_if_needed
					# if such name already exists — add '_1', '_2', …
					_n += 1
					suffix = "_#{_n}"
					redo
				else
					raise FS::KnownError, "(IFile - rename) error: '#{new_path}' already exists"
				end
			end
		end
		super new_path
		@pn = Pathname.new new_path
		self
	end
																																							#~ IFile
	# .full_rename 'new_name.ext'
	# .full_rename 'new_name.ext', add_suffix_if_needed:yes
	def full_rename(new_name, add_suffix_if_needed:nil)
		name, ext = new_name.split /(?=\.[^.]+$)/
		rename name, **({ext:ext, add_suffix_if_needed:add_suffix_if_needed})
	end

	# -change -modify -update
	def change
		lines = pn.readlines
		body = lines.join
		res = yield lines, body
		new_body = res.array? ? res.join : res
		pn.write new_body
	end

	# -checksum -md5
	def md5_checksum
		require 'digest/md5'
		Digest::MD5.hexdigest binread
	end

	# *there is also .delete on IPath level (works with retries)  -delete
	def del!
		FileUtils.rm self.abs_path, force:true
		flush!
	end
end
																																							#~ IFile/



class INodes < Array
	def dirs
		select &:dir?
	end
	def files
		self - dirs
	end
	# preserve class (otherwise will return Array)
	def map
		self.class.new super
	end
end



# File System
module FS
	Conf = {
		touch: 'touch'
	}

	# Error^KnownError < StandardError
	class KnownError < StandardError;end

	#- for module
	class << self
		
		# FS.setup
		#		touch: 'platform/touch/touch'
		def setup(conf)
			Conf.update conf
		end
		
		# conf_FS.rb content sample:
		#	FS.setup(
		#		touch: Dir.pwd+'/platform/touch/touch'
		#	)
		#- suppress^LoadError
		begin
			load 'conf_FS.rb'
		rescue LoadError
		end
		
		# FS.touch
		def touch
			Conf[:touch]
		end
		
		# FS.pwd
		def pwd
			IDir['.']
		end
		
		def del!(path)
			FileUtils.rmtree path
		end
		
		def mv(src, dest)
			FileUtils.mv src, dest
		rescue Errno::EACCES
			# retry few times
			attempt ||= 0
			attempt += 1
			if attempt <= 5
				print ','
				sleep 0.5
				retry
			end
			raise
		end
		
		# FS.chdir dir do
		# *just alias	-cd
		def chdir(*up, &blk)
			Dir.chdir *up, &blk
		end
		alias :cd chdir
		
		# FS.win_fso
		def win_fso
			@win_fso ||= begin
				require 'win32ole'
				WIN32OLE.new 'Scripting.FileSystemObject'
			end
		end
		
		# FS.disks_info['D'] — all drives data is cached on the first call
		# FS.disks_info.add_drives_info
		# FS.disks_info['C'].drives == FS.disks_info['F'].drives — detect same drive
		# FS.disks_info['Q'].drives.first.data.Model | .InterfaceType (USB) | .MediaType (External hard disk media)
		# FS.disks_info.add_drive_types
		#		and after: FS.disks_info['D'].drives.first.data.Type — SSD | HDD | Unspecified (for ext USB drive)
		# FS.disks_info.flush
		def disks_info
			@info_by_disk ||= begin
				h = {}
				rel = self
				for disk in FS.win_fso.Drives
					d = h[disk.DriveLetter] = {obj:disk}
					d.total_b = disk.TotalSize.to_i
					d.label = disk.VolumeName
					# *method added to reflect if free_b or total_b changed (in tests)
					def d.free_perc
						free_b.to_f / total_b * 100
					end
				end
		
				# + .flush
				h.define_singleton_method :flush do
					rel.instance_variable_set :@info_by_disk, nil
				end
		
				# + .update_free
				h.define_singleton_method :update_free do
					for disk in FS.win_fso.Drives
						h[disk.DriveLetter].free_b = disk.AvailableSpace.to_i
					end
				end
		
				# initial update
				h.update_free
		
				# + .add_drives_info (takes 1s)
				drives_data = {}
				h.define_singleton_method :add_drives_info do |_=nil|
					require 'CMDTableParser'
					require '_base/String'
					require '_base/Array'
					require 'set'
					#-- *do cmd calls in parallel (faster)
					thr_1 = Thread.new do
						CMDTableParser.new(
							cmd:'powershell -executionpolicy bypass -File D:/Designing/#Base/cmd/map.ps1',
							title_gap:' ',
							pattern:/^(\w:) +(.+?) +(Disk #\d+, Partition #\d+) +(\d+)$/
						).data
					end
		
					thr_2 = Thread.new do
						CMDTableParser.new(
							cmd:'powershell wmic diskdrive',
						).data
					end
		
					disks_data = thr_1.join.value
					drives_data = thr_2.join.value
					#--
		
					for disk_d in disks_data
						/Disk #(?<drive_index>\d+), Partition #/ =~ disk_d.PartitionName
						drive_d = drives_data.find_by('Index' => drive_index)
						# C: -> C
						disk_letter = disk_d.Name[0]
		
						# add .data method for the index
						drive_index.define_singleton_method :data do
							drives_data.find_by('Index' => self)
						end
						#. *needed to force to store the original string and not the frozen copy (without .data)
						drive_index.freeze
		
						(h[disk_letter].drives ||= Set.new) << drive_index
					end
				end
		
				# + .add_drive_types (SSD, HDD) ( ! takes 2s, call in bg )
				f_drive_types_ready = false
				h.define_singleton_method :add_drive_types do |_=nil|
					# do ignore if^f_drive_types_ready
					next if (f_drive_types_ready)
					drive_types_data = CMDTableParser.new(
							cmd:'PowerShell Get-PhysicalDisk',
							title_gap:' ',
						).data
					for type_d in drive_types_data
						drive_d = drives_data.find_by('Index' => type_d.Number)
						drive_d.Type = type_d.MediaType
					end
					f_drive_types_ready = true
				end
		
				h
			end
		end
	end
end



