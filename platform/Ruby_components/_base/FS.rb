#... require
require 'pathname'
require 'fileutils'
require 'win32/file/attributes'
require '_base/Object'
require '_base/Hash_dot_notation'
# frozen_string_literal: true

PWD_MUTEX = Mutex.new

# D:\statsoft\Ruby\3.0\lib\ruby\3.0.0\pathname.rb
class Pathname
	alias :path to_s
	alias :ext extname

	def name
		@_basename ||= basename.to_s
	end

	def name_no_ext
		name.chomp ext
	end

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


# base class, adaptor for Pathname
class IPath
	attr :base, :pn, :d
																																							#~ IPath\
	# IDir.new(:z_tmp_sync).create
	# base — Pathname | string | true
	def initialize(_path, base:nil)
		# *make path resolved in the current pwd (so dir will be the same even after chdir)
		# - .realpath will fail if path doesn't exist
		# - .expand_path fails if folder is like '~~_builder' (~ expand to user home dir: can't find user ~_builder (ArgumentError))
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

	# dir.link.relative?
	# < PN
	def link
		@pn.readlink
	end
																																							#~ IPath
	# -symlink
	# *if src doesn't exist yet — link will be broken
	# res = symlink_to src, lmtime:dir_up_d.mtime, can_fail:yes
	# if res.failed
	#		res.retry.()
	def symlink_to(src, lmtime:nil, can_fail:false)
		res = {}
		msg = "(symlink_to for '#{self}') failed: src doesn't exist yet: #{src}"
		target = parent/src
		operation = -> do
			target.flush!
			raise msg unless target.exists?
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
				raise msg
			end
		end
		res
	end
																																							#~ IPath
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

	C_attributes = %w[readonly hidden system compressed]
	def attrs(all:false)
		arr = File.attributes pn
		all ? arr : arr & C_attributes
	rescue Errno::ENOENT
		raise "(attrs) ENOENT: #{path}"
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
				file ||= File.new pn
				file.send attr+'=', true
			end
		end
		# *without this .colse the tmp file cannot be deleted (permission denied)
		file.close if file
	end

	# *IFile has .del!
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

	# *used for commans which exit with status 0 and return error in stdout
	private\
	def do_cmd(cmd, prefix:nil)
		err = `#{cmd}`
		if err != ''
			# fix problem that 'attrib' output is in CP866 with cyrillic 'і' replaced with '?'
			if cmd.start_with? 'attrib '
				err = err
					.encode('UTF-8', 'CP866')
					.gsub(/\?/, 'і')   # fix missed cyrillic 'і'
			end
			raise KnownError, "#{prefix}failed: #{err}"
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



# improved -Dir
class IDir < IPath
																																							#~ IDir\
	def dir?
		true
	end

	# dir = IDir.new('z-tmp').create
	# dir.create(:dir_up_d.mtime:)
	def create(mtime:nil)
		tap do |_|
			_.mkpath
			flush!
			if mtime
				mtime = Time.at(mtime) if mtime.numeric?
				_.mtime = mtime
			end
		end
	end

	# src_dir = dir/:src1  -/ -+
	# *returns file in case like: IDir.new(dir_path)/fname (type detected in method_missing)
	def +(up)
		raise "(IDir - /) error: path cannot be empty" if up.nil? || up.to_s.empty?
		# '/' in the beginning causes problem that path becomes from the root of the drive
		super up.to_s.delete_prefix('/')
	end
	alias :/ +

	# -get subdir -[
	# dir[:sub].mtime
	# @dir_local_2['.db/sets/#def_set'] << data_dir
	def [](path)
#		ret = self
#		for name in path.split '/'
#			ret = ret/name
#		ret
		self+path
	end

	def del!
		FileUtils.rmtree self.abs_path
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

	# << array of strings
	#	  reject_by_start: [@db.dir, @tmp_dir.name, 'w.txt'] | '.db'
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

	# << INodes
	# ! slow
	def children
		dirs_files super
	end
	def files
		children.files
	end
	def dirs
		children.dirs
	end

	# 80% faster then .children (uses 2 .globs instead of checking nodes with .dir?, doesn't create objects)
	# - abs:yes — adds 1%
	# << arrays of names/paths
	def fast_children(full:false)
		path_   # cache
		all_names = Dir.glob('*', File::FNM_DOTMATCH, base:@pn.path, sort:false)
		all_names.shift 2   # drop ['.', '..']
		dirs_names = Dir.glob('*/', File::FNM_DOTMATCH, base:@pn.path, sort:false)
		dirs_names.shift 2   # drop ['.', '..']
		dirs_names.each {|_| _.chop! }
		files_names = all_names - dirs_names
		res = {all_names:all_names, dirs_names:dirs_names, files_names:files_names}
		if full
			res.dirs_paths = dirs_names.map {|_| @path_+_ }
			res.files_paths = files_names.map {|_| @path_+_ }
			res.all_paths = res.dirs_paths + res.files_paths
		end
		res
	end


	# -copy dir
	# tmp_dir << 'files/main/find_new_photo' — copy dir (tmp_dir should exist, otherwise it will work as below v)
	# tmp_dir << 'files/main/find_new_photo/' — copy content of a dir (tmp_dir will be created if missed)
	# dest_dir.copy_in src, fix_links:yes
	# - first (dest) folder will be created if doesn't exist
	# - junction are copied as symlinks
	def copy_in(path, fix_links:false, attr:true)
		path = path.to_s
		create unless parent.exists?
		if path.chomp! '/'
			f_copy_content = true
			# *symlinks are copied (relative dir links become broken)
			# *remove_destination=false — causes Errno::EACCES (Permission denied) if the destination file is readonly
			FileUtils.copy_entry path, self, preserve=true, dereference_root=false, remove_destination=true
		else
			f_copy_content = true unless exists?
			FileUtils.cp_r path, self, preserve:true, dereference_root:false
		end

		if fix_links
			src_dir = path.is_a?(IDir) ? path : IDir.new(path)
			unless f_copy_content
				src_dir = src_dir.parent
			end
			fix_links! src_dir, self
		end

		if attr
			# copy all attributes
			src_dir = path.is_a?(IDir) ? path : IDir.new(path)
			self
				.glob('**/*', File::FNM_DOTMATCH)
				.reject {|_| _.name == '.' }
				.each do |node|
					next if node.path == abs_path
					src_node = src_dir/node.relative_path_from(self)
					next if !src_node.exists?
					# file
					if node.file?
						file = IFile.new node
						file.attrs = src_node.attrs
						# *this way doesn't work — https://github.com/chef-boneyard/win32-file-attributes/issues/1
						if false
							flags_bits = File.arrt_flags_bits src_node.path
							File.set_attributes file, flags_bits
						end
																																							#~ IDir - copy_in
					# dir
					else
						dir = IDir.new node
						dir.attrs = src_node.attrs
					end
				end
		end
		self
	end

	alias :<< copy_in

	# copy content of a dir, not the dir itself
	def copy_to(dest)
		dest.create
		# *remove_destination=false — causes Errno::EACCES (Permission denied) if the destination file is readonly
		FileUtils.copy_entry self, dest, preserve=true, dereference_root=false, remove_destination=true
		self
	end
	alias :>> copy_to

	# dir.cd
	def cd
		Dir.chdir self
		self
	end

	# dir.in do
	def in(&block)
		Dir.chdir self, &block
	end

	# (>>>)
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
	def file?
		true
	end

	def dir
		parent
	end

	# *faster then .dir.path
	def dir_path
		File.dirname path
	end

	# -copy file
	# *dest can be file path or dir
	def copy_to(dest)
		if dest.is_a? IDir
			dest.create
		end
		FileUtils.cp self, dest, preserve:true
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

	# dest dir should exist or such file will be created
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
	# -hardlink
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
			raise msg unless target.exists?
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
				raise msg
			end
		end
		res
	end

	# *there is also .delete on IPath level (works with retries)
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
		# *just alias
		def chdir(*up, &blk)
			Dir.chdir *up, &blk
		end
		alias :cd chdir
	end
end

