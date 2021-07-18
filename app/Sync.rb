# bundler setup
	# workaround for path encoding on Windows
	# https://bugs.ruby-lang.org/issues/15993#note-8
	Gem.dir.force_encoding 'UTF-8'
	Gem.path.each {|_| _.force_encoding 'UTF-8' }
	if $:[0].encoding.name == 'Windows-1251'
		$:.each {|_| _.encode! 'UTF-8' }
		$:.push '.'	# somehow it helps, looks like modification of array is needed
	end
	# use Gemfile in the source dir, not in the pwd
	Dir.chdir(__dir__) { require 'bundler/setup' }
#... require
require 'stringio'
require 'set'
require 'digest/sha1'
require 'base64'
require 'PP'
require 'etc'
# load conf.rb
$conf = {}
#- suppress^LoadError
begin
	load 'conf.rb'  # from pwd
rescue LoadError
end
$conf[:components_dir] ||= 'platform/Ruby_components'
# use cofig _base `Core, Object, Nil, Integer, String, Array, Hash, Hash_dot_notation, FS´
$:.push ($conf[:components_dir] || raise('$conf[:components_dir] not defined'))
require '_base/Core'
require '_base/Object'
require '_base/Nil'
require '_base/Integer'
require '_base/String'
require '_base/Array'
require '_base/Hash'
require '_base/Hash_dot_notation'
require '_base/FS'
# use `DirDB_dot_DEV, AndNot, Hub´
require 'DirDB_dot_DEV'
require 'AndNot'
require 'Hub'
require_relative 'ZipEngine'
Thread.abort_on_exception = true



#- refinements
module Refinements
	refine IFile do
		def key
			@key ||= begin
				# *without: [/+] (thus not .base64digest)
				sha1 = Digest::SHA1.digest binread
				Base64.urlsafe_encode64 sha1
			end
		end
	end
end
using Refinements

module Helpers
	WinPathLimit = 247
	# common method and moment for all classes
	def at
		@@at ||= Time.now.to_i
	end
	# *needed for tests
	def set_at!
		@@at = Time.now.to_i
	end
	def pretty_print(pp)
		level = pp.instance_variable_get(:@level) || 1
		if level == 1
			pp.instance_variable_set :@level, level+1
			pp.pp_object self
			pp.instance_variable_set :@level, level
		else
			pp.text inspect
		end
	end
	# *wait needed if initially there is only one task and more will be added in the first thread, so others should wait
	def do_in_parallel(tasks:nil, wait:nil)
		# *with 1 worker only 1 cpu core used
		#  with more workers IO operations are done in parallel
		#  tried cores_n+1 — perfomance slightly worse
		workers_n = Etc.nprocessors
		# workers_n = 1
		if wait
			workers_n.times { tasks << :wait }
		end
		workers = workers_n.times.map do |i|
			Thread.new do
				while task=tasks.shift do
					if :wait == task
						sleep 0.010
						next
					end
					if block_given?
						yield task
					else
						task.()
					end
					 																																					#-#!_ w^[done by =i]
				end
			end
		end
		workers.each &:join
	end
end



class Sync
	include Helpers
	ZipCls = Ruby7Zip

	#- for class
	class << self
		include Helpers
	end
	def Sync.global_filter
		@global_filter ||= Filter.new(db:db).load
	end
	def Sync.db
		@db ||= DirDB.new(db_dir.name, dir:db_dir.parent).load
	end
	def Sync.flush_db
		@db = nil
	end
	def Sync.db_dir
		# *dir should be in pwd
		@db_dir ||= IDir.new 'db_global'
	end
	def Sync.h_storage
		@h_storage ||= StorageHelper.new(sync:self)
	end
	def Sync.flush_h_storage
		@h_storage = nil
	end
	def Sync.db_up
		#. ensure dir_id is saved in storages_data.dat
		#  this can raise NoDefinedStoragesError
		Sync.h_storage.for_each {|_| _.storage_dir }
		# *base.dat needed for h_storage.fast_one
		@db.base.tap do |_|
			_.last_up_at = at
			_.save
		end
		files = @db.filter_map do |k, v|
			next if k == 'device'   # device.dat should not be synced
			db_dir/"#{k}.dat"
		end
		Sync.h_storage.for_each {|_| _.add_update_many files }
	end
	def Sync.db_down
		h_storage.fast_one.tap do |storage|
			names = storage.files.map &:name
			storage.get_many(names, to_dir:db_dir)
		end
		Sync.flush_db
		Sync.db
	end
	def Sync.device
		db.device.id || 'device'
	end
	def Sync.start_dir
		@start_dir ||= IDir.new '.'
	end
	def Sync.tmp_dir
		@tmp_dir ||= IDir.new('z_tmp').create.clear!
	end


	# *.local_dir used in Tree
	attr :local_dir, :db, :files, :dirs, :stats, :ignore_by_path, :tree, :start_dir, :tmp_dir
	def initialize(local:nil, remote:nil, conf:{}, on:nil)
		@remote = remote
		@on = on
		@conf = {
			# *archive file target size, depending of files, result size can be smaller or bigger
			pack_max_size_bytes: 5.MB
		}.update conf
		@on ||= {}   # nil can be passed
		@dirs = []
		@status = {}
		@stats = {}
		set_at!   # *needed for tests
		@hub = Hub.new
		@local_dir = IDir.new local
	end
	def init
		# ignore flag^@f_init_done
		return if @f_init_done
		@f_init_done = true
		raise KnownError, "(init) local path not found: #{@local_dir.abs_path}" unless @local_dir.exists?
		Sync.start_dir   # cache dir
		Sync.db   # *we should call it before any chdir to define proper source dir
		Dir.chdir @local_dir   # work in the local_dir
		@start_dir = IDir.new '.'   # we cannot use @local_dir because of Sync.start_dir
																																										# time_start
																																										_time_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
		@db = DirDB.new
		@db_fn = @db.dir+'.7z'
		@db.load
																																										# time_end2^@db.load
																																										ttime = Process.clock_gettime(Process::CLOCK_MONOTONIC) - _time_start   # total time
																																										w("(@db.load) processed in #{'%.3f' % ttime}")
		# use 'remote:' if provided
		# *this will not created db record
		if @remote
			h_storage.use(
				LocalFS: {
					dir_path: @remote.to_s
				}
			)
		end

		@tree_data = @db.tree_data
		Chunk.set_db @db.data_by_file_key
		@tmp_dir = IDir.new 'z_tmp'
		Shared.skip_root_nodes = [@db.dir, @tmp_dir.name, 'w.txt']
		controller
	end

	def filter
		@filter ||= begin
			init
			Filter.new(db:@db).load
		end
	end

	def h_storage
		@h_storage ||= begin
			init
			StorageHelper.new(sync:self)
		end
	end

	def controller
		@hub.on :broken_links, :hardlink_map_missed do |e, broken_nodes|
																																										w(%Q{e=}+e.inspect)
																																											# w^broken_nodes:
																																											w("broken_nodes:")
																																											# pp^broken_nodes
																																											pp(broken_nodes)
			resolve = -> (choises:nil) do
				f_nothing_fixed = true
				broken_nodes.dup.each do |node|
					if choise=choises[node.path]
						node.resolve choise
						broken_nodes.delete node
						f_nothing_fixed = false
					end
				end
				raise KnownError, "nothing fixed for #{e} (#{broken_nodes.n})" if f_nothing_fixed
				@my_thread.run
			end

			if handler=@on[e]
				handler.call broken_nodes, resolve
			else
				raise KnownError, "on - #{e} handler needed"
			end
		end
	end

	# -up
	def up
																																										w("up")
		Shared.mode = :up   # fail if storage_dir already exists
		init
		# *needed to be able to call .up again
		@status.clear

		# *block can be used for some configurations
		yield if block_given?

		# auth first if tokens missed (one by one for clear workflow)
		h_storage.prepare

		Thread.new do
			Sync.db_up
		rescue NoDefinedStoragesError
			:skip
																																										w("(Sync.db_up) no defined storages -- db_global not synced")
		end
		# *thread needed to be able to stop the process, resolve some issues and then continue
		@my_thread = Thread.new do
			get_nodes!
			build_tree

			@files = @tree.state.added.files + @tree.state.changed.files
																																										w(%Q{@files.n=}+@files.n.inspect)
			make_packs!


			#-- list skipped files
			skipped_due_to_path_limit = @tree.state.skipped.select {|_| _.d.error.is_a? WinPathLimitError }
			other_skipped = @tree.state.skipped - skipped_due_to_path_limit

			# general skipped
			skipped = other_skipped
			if skipped.n > 0
				w ''
				w "! ! ! Skipped files (#{skipped.n}) ! ! !:"
				for file in skipped
					err_part = file.d.error.inspect.sub " - #{file.abs_path}", ''
					w "    #{file.path} -- #{err_part}"
				end
			end

			# skipped items due to Windows MAX_PATH limit
			list_MAX_PATH_skipped_files_and_show_a_solution_hint skipped_due_to_path_limit

			#-- /list skipped files


			@status.f_done = true
		end
																																										#* for profiler to have only 1 thread
		wait_for_results
	end

	def wait_for_results
		# wait for status update from the thread
		loop do |_|
			sleep 0.2
			if @status.f_done
				break
			end
			if @tree.and.state.and.hardlink_map_missed[0]
				@hub.fire :hardlink_map_missed, @tree.state.hardlink_map_missed
			end
			if @tree.and.state.and.link_broken[0]
				@hub.fire :broken_links, @tree.state.link_broken
			end
			# abort on exception iside the thread
			if !@my_thread.alive?
				exit 1
			end
		end
	end
																																							#_ up_inc/

	# -down
	def down
																																										w("down")
		Shared.mode = :down  # use a storage_dir found by name, do not raise
		@local_dir.create   # ensure dir exists
		init
		@tmp_dir.create.clear!

		# *block can be used for some configurations
		yield if block_given?

		# auth first if tokens missed, otherwise .fast_one will fail with a timeout error
		h_storage.prepare

		# update db_global for this device
		# *there is no critical data for down, so we can do it in parallel
		#   only storage tokens can be useful but even this upldate needs fresh tokens
		Thread.new do
																																										# time_start
																																										_time_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
			Sync.db_down
																																										# time_end2^Sync.db_down (in thread)
																																										ttime = Process.clock_gettime(Process::CLOCK_MONOTONIC) - _time_start   # total time
																																										w("(Sync.db_down (in thread)) processed in #{'%.3f' % ttime}")
		rescue NoDefinedStoragesError
			:skip
																																										w("(Sync.db_down) no defined storages -- db_global not synced")
		end
		 																																								# time_start
		 																																								_time_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
		up_db_file = h_storage.fast_one.get @db_fn, to:@tmp_dir
																																										# time_end2^get up_db_file
																																										ttime = Process.clock_gettime(Process::CLOCK_MONOTONIC) - _time_start   # total time
																																										w("(get up_db_file) processed in #{'%.3f' % ttime}")
		# (<!) skip if up db is the same
		if up_db_file.mtime.to_i == @db.base.last_up_at
																																										w("up db is the same - skip")
			return
		end
		 																																								# time_start
		 																																								_time_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
		# db unpack and load
		StringIO.open(up_db_file.binread) do |zip|
			ZipCls.new(zip:zip).unpack_all to:@tmp_dir
			@up_db = DirDB.new @tmp_dir.abs_path
			@up_db.load
			# remove up db files
			@tmp_dir.clear!
		end
		 																																								# time_end2^db unpack and load
		 																																								ttime = Process.clock_gettime(Process::CLOCK_MONOTONIC) - _time_start   # total time
		 																																								w("(db unpack and load) processed in #{'%.3f' % ttime}")
																																										#-#!_ o^@up_db.tree_data
																																										# time_start
																																										_time_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
		#-- process dirs list
		nodes_processed_by_path = {}
		files_to_download_queue = []
		dir_symlinks_failed = []
		file_links_failed = []
		dirs_to_delete = []
		files_to_delete = []
		skipped_due_to_max_path = INodes.new

		tasks = []
		for dir_path, dir_up_d in @up_db.tree_data
			#. skip old deleted dirs or if dir doesn't exists
			next if dir_up_d[:deleted] && (!@tree_data[dir_path] || @tree_data[dir_path][:deleted])
			dir = IDir.new dir_path, base:@local_dir
			tasks << [dir, dir_path, dir_up_d]
		end

		do_in_parallel(tasks:tasks) do |dir, dir_path, dir_up_d|
			next if dir_up_d.excluded
			while !dir.parent.exists?
				# retry few times (it can be created in a parallel thread)
				attempt ||= 0
				attempt += 1
				if attempt > 5
					# was: raise
					puts "(parent.exists?) failed for: #{dir.parent.path}"
					break
				end
				print '^'
				sleep 0.001
			end
			next if !dir.parent.exists?

			# process this dir
			nodes_processed_by_path[dir_path] = 1
			if dir_up_d.deleted
				# (<)
				#. *we should delete dirs and files after all other operations (in some cases file can be used)  (1/3)
				dirs_to_delete << dir
				next
			# dir should exist
			else
				# if exists
				if @tree_data[dir_path] && dir.exists?
					if dir_path != '.'
						# type changed dir/dir_link
						if dir_up_d.link
							# dir > dir_link || link changed
							if !dir.symlink? || dir.link.path != dir_up_d.link
								dir.del!
								# try to create dir symlink
								res = dir.symlink_to dir_up_d.link, lmtime:dir_up_d.mtime, can_fail:true
								if res.failed
									dir_symlinks_failed << res
								end
							end
						elsif dir.symlink? && !dir_up_d.link
							dir.del!
							dir.create(mtime:dir_up_d.mtime)
						end
					end
				# if dir missed
				else
					# create
					if dir_up_d.link
						# try to create dir symlink
						res = dir.symlink_to dir_up_d.link, lmtime:dir_up_d.mtime, can_fail:true
						if res.failed
							dir_symlinks_failed << res
						end
					else
						begin
							dir.create(mtime:dir_up_d.mtime)
						rescue Errno::ENOENT
							# precess ENOENT (detect MAX_PATH)^dir
							if dir.abs_path.length > WinPathLimit
								w "(on_ready) dir skipped due to Windows MAX_PATH limit:\n  #{dir.abs_path}"
								skipped_due_to_max_path << dir
							else
								pputs "(on_ready) ENOENT: #{dir.path}"
								puts $!
								puts $@.first 7
							end
							# (<) do not process dir attrs and files
							next   # dir
						end
					end
				end
			end
																																							#~ down
			# (<) if link — do not process files
			next if dir_up_d.link
			# update attrs
			dir.attrs = dir_up_d.attrs || []
			# process dir files
			path_ = dir.path_
			for fname, file_up_d in dir_up_d.files
				next if file_up_d.excluded
				f_down = nil
				fpath = path_+fname
				file = IFile.new fpath
				if file_up_d.deleted
					#. *we should delete dirs and files after all other operations (in some cases file can be used)  (2/3)
					files_to_delete << file
					nodes_processed_by_path[fpath] = 1
				# if file should exist
				else
					# if file data or file exists
					if (file_d=@tree_data[dir_path]&.files[fname]) || file.lexists?
						nodes_processed_by_path[fpath] = 1

						# type changed file/file_link
						if file_up_d.link
							# file > file_link || link changed
							if !file.symlink? || file.link.path != file_up_d.link
								file.del!
								# try to create file symlink
								res = file.symlink_to file_up_d.link, lmtime:file_up_d.mtime, can_fail:true
								if res.failed
									file_links_failed << res
								end
							else
								next
							end
						elsif file_up_d.hard_link
							# file > file_link || link changed
							if !file.hardlink? || file_d.and.hard_link != file_up_d.hard_link
								file.del!
								# try to create file hardlink
								res = file.hardlink_to file_up_d.hard_link, can_fail:true
								if res.failed
									file_links_failed << res
								end
							else
								next
							end
						# file_link > file
						# removed:  ||  file.hardlink? && !file_up_d.hard_link
						#		 because main files always become hardlinks or user can make a hardlink from any file and it is ok
						elsif file.symlink? && !file_up_d.link || file_d.and.hard_link && !file_up_d.hard_link
							file.del!
							f_down = true
						# if same version — skip (fix mtime if needed)
						# *(!)if local file was changed but in local db key is old — file will not be updated
						#   to change this just use file.key here (should be big slowdown, better to check mtime and if it is not changed — use versions.last)
						elsif file.lexists? && (file_d.and.versions.and.last || file.key) == file_up_d.versions.last
							update_file file, file_up_d
							next
						else   # file changed or missed
							f_down = true
						end
					# if file missed in db
					else
						# if link — create
						if file_up_d.link
							# try to create file symlink
							res = file.symlink_to file_up_d.link, lmtime:file_up_d.mtime, can_fail:true
							if res.failed
								file_links_failed << res
							end
						elsif file_up_d.hard_link
							# try to create file hardlink
							res = file.hardlink_to file_up_d.hard_link, can_fail:true
							if res.failed
								file_links_failed << res
							end
						else
							f_down = true
						end
					end

					if f_down
						# (<) if chunk is available (like when file renamed or there is a copy) — reuse
						key = file_up_d.versions.last
						# *files arr can be empty if all the file instances deleted
						if chunk=Chunk[key]
							same_file = catch :found do
								for path in chunk.files
									same_file = IFile.new path
									if same_file.exists?
										throw :found, same_file
									end
								end
								nil
							end

							if same_file
								same_file.copy_to file.abs_path
								update_file file, file_up_d
								# *do not download
								next   # file
							end
						end

						files_to_download_queue << {
							fpath:fpath,
							mtime:file_up_d.mtime,
							attrs:file_up_d.attrs,
							file_key: file_up_d.versions.last
						}
					end
				end
			end
		end

		# *we should delete dirs and files after all other operations (in some cases file can be used)  (3/3)
		files_to_delete.each &:del!
		dirs_to_delete.each &:del!
																																							#~ down
		# retry failed dir symlink creations
		for res in dir_symlinks_failed
			res.retry.()
		end
		# process local tree — delete not marked nodes
		# *proc needed to localize vars: dir, file
		proc do
			for dir_path, dir_d in @tree_data
				dir = IDir.new dir_path
				if !nodes_processed_by_path[dir_path]
					dir.del!
					next
				end
				next if dir_d.link   # do not process files in symlinks
				for fname, file_d in dir_d.files
					file = dir/fname
					if !nodes_processed_by_path[file.path]
						file.del!
					end
				end
			end
		end.()
		 																																								w(%Q{files_to_download_queue.n=}+files_to_download_queue.n.inspect)
																																							#~ down
		@stats.files_downloaded = files_to_download_queue.n
																																										# time_end2^state scan
																																										ttime = Process.clock_gettime(Process::CLOCK_MONOTONIC) - _time_start   # total time
																																										w("(state scan) processed in #{'%.3f' % ttime}")
																																										# time_start
																																										_time_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
		loading_packs = []
		# files download_queue
		# {fpath, file_key}
		files_to_download_queue.each do |file_d|
			d=@up_db.data_by_file_key[file_d.file_key]
			on_ready = -> (file_body) do
				file = IFile.new file_d.fpath
				file.binwrite file_body
				# fix mtime for some files (chunk is the same but mtime differ)
				update_file file, file_d
				file.dir.mtime = @up_db.tree_data[file.dir_path].mtime
			rescue Errno::ENOENT
				# precess ENOENT (detect MAX_PATH)^file
				if file.abs_path.length > WinPathLimit
					w "(on_ready) file skipped due to Windows MAX_PATH limit:\n  #{file.abs_path}"
					skipped_due_to_max_path << file
				else
					pputs "(on_ready) ENOENT: #{file.path}"
					puts $!
					puts $@.first 7
				end
			rescue Errno::EACCES, Errno::EINVAL
				# retry few times
				attempt ||= 0
				# if attempt == 0
				# 	p :src:, :file_d.fpath:
				attempt += 1
				if attempt <= 5
					file.del!
					sleep 0.5
					print ','
					retry
				else
					pputs "(on_ready) failed: #{$!}"
					puts $@[0]
				end
			end

			#! in async it may return promise, so we can do .then (correct one) here
			loading_packs << {pack_name:d.pack_name, file_key:file_d.file_key, on_ready:on_ready}
		end
																																							#~ down
		# {pack_name, file_key, on_ready} --> {pack_name => [{pack_name, file_key, on_ready}, …]}
		loading_packs_by_name = loading_packs.group_by &:pack_name
		@stats.packs_downloaded = loading_packs_by_name.length
		tasks = []
		pack_index = 0
		loading_packs_by_name.each do |pack_name, arr; _time_start|
			tasks << -> do
																																										# time_start
																																										_time_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
				pack_index += 1
				fname = pack_name+'.7z'
				task_title = "#{pack_index})"
																																										w("get: #{task_title} #{fname} ...")
				# download
				up_pack_file = h_storage.fast_one.get fname, to:@tmp_dir
																																										w("... got #{task_title} #{up_pack_file.size.hr}")
				d_arr_by_file_key = arr.group_by &:file_key
				fnames = d_arr_by_file_key.keys
				StringIO.open(up_pack_file.binread) do |zip|
					ZipCls.new(zip:zip).unpack_files(fnames) do |fname, file_body|
						d_arr = d_arr_by_file_key[fname]
						for d in d_arr
							d.on_ready.call file_body
						end
					end
				end
				 																																						w("... done #{task_title} #{fnames.n} files")
				up_pack_file.del!
				 																																						# time_end^    in #{'%.3f' % ttime}
				 																																						ttime = Process.clock_gettime(Process::CLOCK_MONOTONIC) - _time_start   # total time
				 																																						w("    in #{'%.3f' % ttime}")
			end
		end
		do_in_parallel(tasks:tasks)

		# - all files ready -

		# retry failed file symlink creations
		for res in file_links_failed
			res.retry.()
		end
		 																																								# time_end2^download + unpack files
		 																																								ttime = Process.clock_gettime(Process::CLOCK_MONOTONIC) - _time_start   # total time
		 																																								w("(download + unpack files) processed in #{'%.3f' % ttime}")
																																										# time_start
																																										_time_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
		#-- fix dirs mtime after changes
		tasks = []
		for dir_path, dir_up_d in @up_db.tree_data
			next if dir_path == '.'
			dir = @local_dir/dir_path
			tasks << [dir, dir_up_d]
		end

		do_in_parallel(tasks:tasks) do |dir, dir_up_d|
			if dir.exists?
				if dir.symlink?
					if dir.lmtime.to_i != dir_up_d.mtime.to_i
						dir.lmtime = dir_up_d.mtime
					end
				else
					if dir.mtime.to_i != dir_up_d.mtime.to_i
						dir.mtime = dir_up_d.mtime
					end
				end
			end
		end
		 																																								# time_end2^fix dirs mtime
		 																																								ttime = Process.clock_gettime(Process::CLOCK_MONOTONIC) - _time_start   # total time
		 																																								w("(fix dirs mtime) processed in #{'%.3f' % ttime}")
		 																																								# time_start
		 																																								_time_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
		# swap db data
		for k, v in @up_db
			@db.send "#{k}=", v
		end
		@db.save
		 																																								# time_end2^update db
		 																																								ttime = Process.clock_gettime(Process::CLOCK_MONOTONIC) - _time_start   # total time
		 																																								w("(update db) processed in #{'%.3f' % ttime}")
		# list skipped items due to Windows MAX_PATH limit
		skipped_due_to_max_path.tap do |skipped|
			@stats.skipped_due_to_max_path = skipped.n
			list_MAX_PATH_skipped_files_and_show_a_solution_hint skipped
		end

		@tmp_dir.del!
	end
																																							#~ down/

	def build_tree
																																										w("-- build_tree --")
																																										# time_start
																																										_time_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
		@tree = Tree.new(sync:self, db:@tree_data, dirs:@dirs)
																																										# time_end2^Tree.new
																																										ttime = Process.clock_gettime(Process::CLOCK_MONOTONIC) - _time_start   # total time
																																										w("(Tree.new) processed in #{'%.3f' % ttime}")
																																											# w^@tree.stats:
																																											w("@tree.stats:")
																																											# pp^@tree.stats
																																											pp(@tree.stats)
		 																																								#-#!_ o^@tree_data
		# resolve issues
		loop do
			if @tree.state.link_broken[0] || @tree.state.hardlink_map_missed[0]
				((( Thread.stop )))  # wait for resolution
			else
				break
			end
		end
	end


	def make_packs!
																																										w("-- make_packs! --")
		 																																								# time_start
		 																																								_time_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
		@tmp_dir.create
		pack_id = @db.base.last_pack_id || 0
		if @files.empty?
			w '(make_packs!) no files to add - skip pack creation, backup only db'
		else
			uploading_threads = []
			limit = @conf.pack_max_size_bytes
			diff_size_ok = (limit * 0.05).to_i
			target_pack_size = limit + diff_size_ok
			zip = last_min_size_diff = f_one_big_file = nil

			reset_pack = -> do
				zip = ZipCls.new
				last_min_size_diff = target_pack_size
				f_one_big_file = false
			end
			reset_pack.()

			files_queue = @files.sort_by &:mtime   # (old -> new)
			# *needed for stable tests
			files_queue.sort_by! {|_| [_.mtime, _.size] } if DirDB.dev?
			removed_files = []
			removed_files_total_compressed_size = 0
			f_force_add = false
			skipped_n = 0
			skipped_total_size = 0
			while file=files_queue.shift
				# skip if file is already in some pack
				if file.chunk
					# skip
					skipped_n += 1
					skipped_total_size += file.size
				else
					# *use file_key instead of name to avoid collisions
					#  do not add ext because files with different ext may have same content
					file_compressed_size = zip.add file, as:file.key
					# mark that a file is now in some pack, so same files will be skipped
					file.create_chunk
				end
				unless f_force_add
					size_diff = (target_pack_size - zip.size).abs
					if size_diff > last_min_size_diff || zip.size > target_pack_size
						if zip.files.n == 1
							f_one_big_file = true
						else
							zip.rem_last
							file.delete_chunk
							removed_files << file
							removed_files_total_compressed_size += file_compressed_size
							size_diff = last_min_size_diff
						end
					else
						last_min_size_diff = size_diff
					end
				end
																																							#~ make_packs!
				# (<) if not many files remained — add to the last pack
				if files_queue.empty? && removed_files.not.empty? && removed_files_total_compressed_size < target_pack_size/2
					# re-add removed files
					files_queue.unshift *removed_files
					removed_files.clear
					removed_files_total_compressed_size = 0
					f_force_add = true
					# * continue to process files_queue
					next
				end

				# finish this pack
				if f_one_big_file || size_diff < diff_size_ok || files_queue.empty?
					if zip.files.not.empty?
						total_files_size = zip.files.sum &:size
						pack_id += 1
						# ID_dateFrom-dateTo
						pack_name = pack_id.to_s
						[zip.files.first, zip.files.last].each do |_|
							pack_name += '_' + _.mtime.strftime("%Y.%m.%d")
						end
						pack_fn = pack_name+'.7z'
						pack_file = @tmp_dir/pack_fn
						uploading_threads << Thread.new(zip, pack_name, pack_file) do |zip, pack_name, pack_file|
							# archive
							zip.save_as pack_file
																																										w(" > > >  #{pack_file.name} (#{pack_file.size.hr})")
							# update files chunks (should be after .save_as)
							zip.files.each do |_|
								_.chunk.update(
									pack_name:pack_name
								)
							end

							# move archive to remote dir
							h_storage.for_each {|_| _.add_update pack_file }

							pack_file.del!
						end
					end

					f_last_file = files_queue.empty? && removed_files.empty?
					unless f_last_file
																																										w(%Q{removed_files.n=}+removed_files.n.inspect)
						# re-add removed files
						files_queue.unshift *removed_files
						removed_files.clear
						removed_files_total_compressed_size = 0
						# start new pack
						reset_pack.()
					end
				end
			end
						# * continue to process files_queue
																																							#~ make_packs!
			# *we should wait for all packs threads to finish (there is chunk.update and zip_data removed from files data)
			uploading_threads.each &:join
																																										# w^Skipped files: =skipped_n (=skipped_total_size.hr) -- deduplication
																																										w("Skipped files: #{skipped_n} (#{skipped_total_size.hr}) -- deduplication")
																																										# time_end2^make_packs!
																																										ttime = Process.clock_gettime(Process::CLOCK_MONOTONIC) - _time_start   # total time
																																										w("(make_packs!) processed in #{'%.3f' % ttime}")
		end
		# update db
		 																																								# time_start
		 																																								_time_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
		@tree.save
																																										# time_end2^@tree.save
																																										ttime = Process.clock_gettime(Process::CLOCK_MONOTONIC) - _time_start   # total time
																																										w("(@tree.save) processed in #{'%.3f' % ttime}")
		Chunks.save
																																										# time_start
																																										_time_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

		@db.base.tap do |_|
			_.last_up_at = at
			_.last_pack_id = pack_id
			_.save
		end
		# add base.dat separately (needed for detecting full fast_one storage for down)
		base_uploading_thread = Thread.new do
			base_file = IFile.new @db.dir+'/base.dat'
			h_storage.for_each {|_| _.add_update base_file }
		end
		# archive db
		db_file = @tmp_dir/@db_fn
		ZipCls.new(fp:db_file).pack_dir @db.dir
		# … and move to destination
		h_storage.for_each {|_| _.add_update db_file }
		# *we should wait for this thread before tmp_dir deletion
		base_uploading_thread.join

		@tmp_dir.del!
		 																																								# time_end2^update and backup db
		 																																								ttime = Process.clock_gettime(Process::CLOCK_MONOTONIC) - _time_start   # total time
		 																																								w("(update and backup db) processed in #{'%.3f' % ttime}")
	end
																																							#~ make_packs!/

	def get_nodes!
																																										# time_start
																																										_time_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
		#-- process full tree
		# *process only folders recursively

		# skip special root dirs
		@ignore_by_path = {}
		@ignore_by_path[@db.dir] = 1
		@ignore_by_path[@tmp_dir.path] = 1

		# include . root
		@dirs = [[@local_dir.path, nil]]

		tasks = []
		get_dirs = -> (path) do
			path_ = path == '.' ? '' : path+'/'
			# *with sorting, in some dirs ['.', '..'] are not the first 2 items and the recursion never ends
			dirs_names = Dir.glob('*/'.freeze, File::FNM_DOTMATCH, base:path, sort:false)
			# drop ['.', '..']
			dirs_names.shift 2
			if dirs_names[0]
				#. build full path for each dir
				dirs_paths = dirs_names.each {|_| _.prepend(path_).chop! }
				parent_path = path
				for path in dirs_paths
					next if @ignore_by_path[path]
					@dirs << [path, parent_path]
					# do not follow symlinks
					# *this .symlink? is expensive (+30%)
					unless File.symlink? path
						tasks << path
					end
				end
			end
		end

		tasks << @local_dir.path
		do_in_parallel(tasks:tasks, wait:true) do |path|
			get_dirs.(path)
		end
		 																																								# time_end2^get_nodes!
		 																																								ttime = Process.clock_gettime(Process::CLOCK_MONOTONIC) - _time_start   # total time
		 																																								w("(get_nodes!) processed in #{'%.3f' % ttime}")
																																										w(%Q{@dirs.n=}+@dirs.n.inspect)
	end

	def update_file(file, file_d)
		if file.mtime.to_i != file_d.mtime
			file.mtime = file_d.mtime
		end
		# update attrs
		file.attrs = file_d.attrs || []
	end

	def list_MAX_PATH_skipped_files_and_show_a_solution_hint(skipped)
		if skipped.n > 0
			w ''
			w "! ! ! Skipped items due to Windows MAX_PATH limit (#{skipped.n}) ! ! !:"
			for node in skipped
				w '    ' + node.inspect
			end

			# create LongPathsEnabled.reg
			reg_file = Sync.start_dir/'LongPathsEnabled.reg'
			reg_file.write <<~'LINES'
				Windows Registry Editor Version 5.00

				[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\FileSystem]
				"LongPathsEnabled"=dword:00000001
			LINES

			# show the solution hint
			w ''
			w '  It is a known problem and can be resolved in a minute.'
			w "  1) Find a special file #{Sync.start_dir.abs_path}/LongPathsEnabled.reg"
			w '  2) Open it (UAC elevation required) and then delete it.'
			w '  3) Now close the current sync process and run the operation again — it should now redo those skipped items.'
			w '  You can read more about this solution here: https://docs.microsoft.com/en-us/windows/win32/fileio/maximum-file-path-limitation?tabs=cmd#enable-long-paths-in-windows-10-version-1607-and-later'
		end
	end


	def inspect
		to_s
	end
end
																																							#~ Sync/


# -tree
class Tree
	include Helpers
	@@id = 0
																																							#~ Tree\
	attr :sync, :hub, :db, :root_dir, :dirs, :state, :stats, :tdir_by_path, :all_dirs
	def initialize(sync:nil, db:nil, dirs:nil)
		@sync = sync
		@db = db
		@id = @@id += 1
		@all_dirs = []
		@tdir_by_path = {}
		@root_dir = @sync.local_dir
		@state = {
			added: INodes.new,
			changed: INodes.new,
			removed: INodes.new,
			link_added: INodes.new,
			link_broken: INodes.new,
			hardlink_map_missed: INodes.new,
			excluded: INodes.new,
			skipped: INodes.new,
			dirs_skipped_by_path: {}
		}
		@stats = {
			dir_added: 0,
			file_added: 0,
			dir_changed: 0,
			file_changed: 0,
			dir_removed: 0,
			file_removed: 0,
			dir_link_added: 0,
			file_link_added: 0,
			dir_link_broken: 0,
			file_link_broken: 0,
			file_hardlink_map_missed: 0,
			dir_excluded: 0,
			file_excluded: 0,
			dir_skipped: 0,
			file_skipped: 0
		}
		@hub = Hub.new
		%w[added changed removed link_added link_broken hardlink_map_missed excluded skipped].each do |action|
			@hub.on :"file_#{action}", :"dir_#{action}" do |e, node_path, node|
				@state[action.to_sym] << node_path
				@stats[e] += 1
				if e == :dir_excluded && @state[:added].includes?(node)
					@state[:added].delete node
					@stats[:dir_added] -= 1
				end
			end
		end

		# define @`Dir´ class
		@Dir = Class.new Dir
		@Dir.set_tree self
		self.class.const_set('Dir_'+@id.to_s, @Dir)
																																							#~ Tree
		# build state from DB
		for d_path, dir_d in @db
			parent_path = ::File.dirname d_path
			parent_tdir = @tdir_by_path[parent_path]
			tdir = @Dir.new d_path, parent_tdir:parent_tdir
			@tdir_by_path[d_path] = tdir
			@all_dirs << tdir
		end

		# add new dirs
		for path, parent_path in dirs
			parent_tdir = @tdir_by_path[parent_path]
			begin
				@tdir_by_path[path] ||= @Dir.new(path, parent_tdir:parent_tdir).tap do |tdir|
					@all_dirs << tdir
				end
			rescue Errno::ENOENT
				e = $!
				dir = IDir.new path
				if e.is_a?(Errno::ENOENT) && dir.abs_path.length > WinPathLimit
					e = WinPathLimitError.new 'skipped due to Windows MAX_PATH limit'
				end
				dir.d.error = e
				@state.dirs_skipped_by_path[path] = 1
				@hub.fire :dir_skipped, dir
																																										w("dir skipped - #{dir} (#{e.inspect})")
			end
		end
		 																																								w("(Tree) update state")
		# update state (IO operations can be done in parallel)
		# *tried to make tasks with groups of 10-50-100 dirs updates — doesn't help
		do_in_parallel(tasks:@all_dirs.dup) do |dir|
			dir.update
		end

		# calc total size
		@stats.files_added_size = @state.added.files.sum(&:size).hr
		@stats.files_changed_size = @state.changed.files.sum(&:size).hr
		# *we cannot get size of deleted file and we do not store it in file.d
		# @stats.files_removed_size = @state.removed.files.sum(&:size).hr
	end

	def save
		#. *sorting needed for tests to compare results (after adding processing in threads)
		@db.replace @db.sort.to_h if DirDB.dev?
		@db.save
	end
	def inspect
		to_s
	end
end
																																							#~ Tree/



# -dir
class Tree::Dir < IDir
	include Helpers
																																							#~ Tree::Dir\
	#- for class
	class << self
		def set_tree(tree)
			@@tree = tree
			@@hub = tree.hub
		end
	end

	attr :path, :d, :dirs, :tfiles, :filter, :parent_tdir
	def initialize(dir_path, parent_tdir:nil)
		@parent_tdir = parent_tdir
		super dir_path
		@path = dir_path
		set_base @@tree.root_dir
		@filter = DirFilter.new dir:self
		@resolved = {}
		@f_is_root_dir = self == @@tree.root_dir
		define_d
	end

	def tree
		@@tree
	end

	def define_d
		@d=@@tree.db[path] ||= begin
			if symlink?
				@@hub.fire :dir_link_added, self
																																										w("dir link added - #{self.inspect}")
				{link:link.path}
			else
				if Shared.mode == :up
					# check if the folder is accessible
					# *it will fail for example in case of WinPathLimitError
					lmtime
				end
				@f_new_dir = true
				{dirs:{}, files:{}}
			end
		end
	end
	def update
		# ignore flag^@f_updated
		return if @f_updated
		@f_updated = true
		# build state from DB
		@tfile_by_name = {}
		@tdir_by_name = {}
		if @d.link
			@tfiles = []
			@tdirs = []
		else
			path_   # cache
			@tfiles = @d.files.keys.map do |fname|
				Tree::File.new(@path_+fname, tdir:self, excluded: @filter.excludes?(fname) )
					.tap {|_| @tfile_by_name[fname] = _ }
			end
			@tdirs = @d.dirs.keys.map do |dname|
				#. *optimized way instead of using  self+dname
				dpath = @f_is_root_dir ? dname : @path_+dname
				@@tree.tdir_by_path[dpath]
					.tap {|_| @tdir_by_name[dname] = _ }
			end
		end
																																							#~ Tree::Dir

		# *updates excluded flag
		@filter.init

		# *this should be after @filter.init
		if @f_new_dir && !@d.excluded
			@@hub.fire :dir_added, self
																																										w("dir added - #{self.inspect}")
		end
		# check current state
		if exists? && !@@tree.sync.ignore_by_path[abs_path]
			@d.delete :deleted   # restore if was deleted
			# update attrs
			attrs.then do |_|
				if _.empty?
					@d.delete :attrs
				else
					@d.attrs = _
				end
			end
			if symlink?
				if link.path != @d.link
					@d.delete_keys! :dirs, :files
					@d.link = link.path
					@@hub.fire :dir_changed, self
				end
				@d.mtime = lmtime.to_i unless @f_is_root_dir
			else
				# dir_link > dir
				if @d.link
					if @resolved.dir_ok
						# convert to normal dir
						@d.replace(dirs:{}, files:{})
						@@hub.fire :dir_added, self
						f_dir_ok = true
																																											w("dir added - #{self.inspect}")
					elsif @resolved.restore
						#- do not change mtime for^parent
						was_mtime = parent.mtime
						del!
						symlink_to @d.link, lmtime:@d.mtime
						parent.mtime = was_mtime
					else
						@f_broken = true
						# *ask user for resolution
						@@hub.fire :dir_link_broken, self
					end
				else
					f_dir_ok = true
				end
																																							#~ Tree::Dir
				if f_dir_ok
					@d.mtime = mtime.to_i unless @f_is_root_dir
					_ = fast_children full:true
					files_names = _[:files_names]
					files_paths = _[:files_paths]
					dirs_names = _[:dirs_names]
					dirs_paths = _[:dirs_paths]

					files_paths.each_with_index do |file_path, i|
						fname = files_names[i]
						# skip_root_nodes (1/2)
						if @f_is_root_dir
							next if fname.in? Shared.skip_root_nodes
						end

						# add new if needed
						@tfile_by_name[fname] ||= begin
							Tree::File.new(file_path, tdir:self, excluded: @filter.excludes?(fname) )
								.tap {|_| @tfiles << _ }
						end
					rescue Errno::EACCES, Errno::EINVAL, Errno::ENOENT
						e = $!
						file = IFile.new file_path
						if e.is_a?(Errno::ENOENT) && file.abs_path.length > WinPathLimit
							e = WinPathLimitError.new 'skipped due to Windows MAX_PATH limit'
						end
						file.d.error = e
						@@hub.fire :file_skipped, file
																																										w("file skipped - #{file} (#{e.inspect})")
					end
					dirs_paths.each_with_index do |dir_path, i|
						dname = dirs_names[i]
						# skip_root_nodes (2/2)
						if @f_is_root_dir
							next if dname.in? Shared.skip_root_nodes
						end
						# add new if needed
						@tdir_by_name[dname] ||= begin
							@d.dirs[dname] = 1
							dir = @@tree.tdir_by_path[dir_path]
							if !dir && !@@tree.state.dirs_skipped_by_path[dir_path]
								raise("folder not found in tdir_by_path: #{dir_path}")
							end
							@tdirs << dir
							dir
						end
					end
					# update all files
					@tfiles.each &:update
				end
			end

			if @parent_tdir&.excluded?
				exclude
			end

		# if deleted
		else
			delete
		end

		self
	end
																																							#~ Tree::Dir
	# (>>>)
	def delete
		# ignore if^@d.deleted || @d.excluded
		return if (@d.deleted || @d.excluded)
		update   # ensure updated
		@d.deleted = {at:at}
		@parent_tdir.d.dirs.delete name
		@@hub.fire :dir_removed, self
																																										w("dir removed - #{self.inspect}")
		# delete files
		@tfiles.each &:delete
		# delete sub dirs
		@tdirs.each do |_|
			@d.dirs.delete _.name
			_.delete  # (>>>)
		end
	end
	def exclude
		update   # ensure updated
		# ignore if^@d.excluded
		return if (@d.excluded)
		@d.excluded = {at:at}
		@@hub.fire :dir_excluded, @path, self
																																										w("dir_excluded - #{self.inspect}")
	end
	def excluded?
		@d.excluded
	end
	def unexclude
		@d.delete :excluded
	end

	def resolve(choise)
		case choise
			when :restore, :dir_ok
				@resolved[choise] = 1
				@f_broken = false
				@f_updated = false
				update
			else
				raise KnownError, "(resolve) wrong choise: #{choise}"
		end
	end
	def pretty_print_instance_variables
		[:path, :@d, :@tfiles]
	end
end
																																							#~ Tree::Dir/


# -file
class Tree::File < IFile
	include Helpers
																																							#~ Tree::File\
	attr :path
	def initialize(file_path, tdir:nil, excluded:nil)
		@tdir = tdir
		@excluded = excluded
		super file_path
		@path = file_path
		@resolved = {}
		@hub = @tdir.tree.hub
		define_d
	end

	def define_d
		@d=@tdir.d.files[name] ||= begin
			if @excluded
				@f_just_excluded = true
				{}
			elsif symlink?
				@hub.fire :file_link_added, self
																																									w("file symlink added - #{self.inspect}")
				{link:link.path}
			elsif hardlink? && as_hardlink?
				@hub.fire :file_link_added, self
																																									w("file hardlink added - #{self.inspect}")
				{hard_link:@resolved.hard_link}
			else
				{
					mtime: mtime.to_i,
					versions: [key]
				}.tap do |_|
					_.as_file = 1 if hardlink? && as_file?
					@hub.fire :file_added, self
																																									w("file added - #{self.inspect}")
				end
			end
		rescue MissedLinkError
			@f_broken = true
			nil
		end
	end
																																							#~ Tree::File
	def update
		# ignore if^@f_broken
		return if (@f_broken)
		if @excluded
			# *mark as excluded only if file was in db
			if @f_just_excluded
				# *do not add to db at all
				@tdir.d.files.delete name
			elsif !@d.excluded
				@hub.fire :file_excluded, @path
																																										w("file excluded - #{self.inspect}")
				@d.excluded = {at:at}
				# update chunks
				@d.versions.and.each do |_|
					Chunk[_].unbind_file path
				end
				@d.delete_keys! :mtime, :versions
			end

		# if exists
		elsif exists? || lexists?
			if @d.deleted
				@d.delete :deleted   # restore if was deleted
				chunk   # rebind to chunk
				@hub.fire :file_added, self
																																									w("file restored - #{self.inspect}")
			end
			if @d.excluded
				@d.delete :excluded   # restore
				@d.mtime = mtime.to_i
				@d.versions = [key]
				chunk   # rebind to chunk
				@hub.fire :file_added, self
																																									w("file re-included - #{self.inspect}")
			end
			# update attrs
			attrs.then do |_|
				if _.empty?
					@d.delete :attrs
				else
					@d.attrs = _
				end
			end
			if symlink?
				@d.mtime = lmtime.to_i
				if @d.link
					if link.path != @d.link
						@d.link = link.path
						@hub.fire :file_link_changed, self
																																									w("file symlink changed - #{self.inspect}")
					end
				# file_hardlink > file_link
				elsif @d.hard_link
					@d.delete :hard_link
					@d.link = link.path
					@hub.fire :file_link_changed, self
				# file > file_link
				else
					delete   # this will delete related chunks, not file
																																									w("file symlink added - #{self.inspect}")
					@d.delete_keys! :versions, :deleted
					@d.link = link.path
					@hub.fire :file_link_added, self
				end
																																							#~ Tree::File - update
			elsif hardlink? && as_hardlink?
				if @d.hard_link
					if @resolved.hard_link
						if @resolved.hard_link != @d.hard_link
							@d.hard_link = @resolved.hard_link
							@hub.fire :file_link_changed, self
																																									w("file hardlink changed - #{self.inspect}")
						end
						fix_link_if_broken!
					elsif @resolved.restore
						# *same @d.hard_link
						fix_link_if_broken!
					end

					unless FileUtils.compare_file(self, dir/@d.hard_link)
						@f_broken = true
						# *ask user for resolution
						@hub.fire :file_link_broken, self
					end

				# file_hardlink > file_link
				elsif @d.link
					@d.delete :link
					@d.hard_link = @resolved.hard_link
					@hub.fire :file_link_changed, self
				# file > file_hardlink
				else
					delete   # this will delete related chunks, not file
																																									w("file hardlink added - #{self.inspect}")
					@d.delete_keys! :versions, :deleted
					@d.hard_link = @resolved.hard_link
					@hub.fire :file_link_added, self
					fix_link_if_broken!
				end

				@d.mtime = mtime.to_i
																																							#~ Tree::File - update
			else
				# file_link > file
				# file_hardlink > file
				if @d.link || @d.hard_link
					if @resolved.file_ok
						# convert to normal file
						@d.replace(mtime: mtime.to_i, versions: [key])
						@hub.fire :file_added, self
																																									w("file added - #{self.inspect}")
					elsif @resolved.restore
						#- do not change mtime for^dir
						was_mtime = dir.mtime
						del!
						# *tried to define method make_link in each subclass and use here
						#   but failed because current class can be wrong (chosend based on real file)
						if @d.link
							symlink_to @d.link, lmtime:@d.mtime
						else
							hardlink_to @d.hard_link
						end
						dir.mtime = was_mtime
					else
						@f_broken = true
						# *ask user for resolution
						@hub.fire :file_link_broken, self
																																									w("file link broken - #{self.inspect}")
					end
				# if modified
				elsif mtime.to_i != @d.mtime
					# update file data
					@d.mtime = mtime.to_i
					if key != @d.versions.last
						#. unbind from current chunk
						Chunk[@d.versions.last].and.unbind_file path
						@d.versions << key
						@hub.fire :file_changed, self
																																										w("file changed - #{self.inspect}")
					end
				end
			end
		# if deleted
		else
			delete
		end
	rescue MissedLinkError
		@f_broken = true
	end
																																							#~ Tree::File
	def chunk
		Chunk[key].tap do |_|
			_.and.bind_file path
		end
	end
	def create_chunk
		Chunk.create key
	end
	def delete_chunk
		Chunk.delete key
	end
	def delete
		# ignore if^@d.deleted || @d.excluded
		return if (@d.deleted || @d.excluded)
																																										w("file removed - #{self.inspect}")
		@hub.fire :file_removed, self
		@d.deleted = {at:at}
		# update chunks
		# *link doesn't have chunks
		# *це нам дасть можливість підрахувати скільки у паках видалених даних
		@d.versions.and.each do |_|
			Chunk[_].and.unbind_file path
		end
	end
	def as_file?
		return true if @d.and.as_file || @resolved.as_file
	end
	def as_hardlink?
		return true if @d.and.hard_link || @resolved.hard_link
		return false if @d.and.as_file || @resolved.as_file
		# *ask user for resolution
		@hub.fire :file_hardlink_map_missed, self
		raise MissedLinkError, "(File) Hardlink map missed for: #{path}"
	end
	def fix_link_if_broken!
		if !hardlink? || !(FileUtils.compare_file self, dir/@d.hard_link)
			#- do not change mtime for^dir
			was_mtime = dir.mtime
			del!
			hardlink_to @d.hard_link
			dir.mtime = was_mtime
		end
	end
	def resolve(choise)
		case choise
			when String
				@resolved.hard_link = choise
			when :as_file   # file should be copied as normal
				@resolved.as_file = 1
				@d.as_file = 1 if @d
			when :restore, :file_ok
				@resolved[choise] = 1
			else
				raise KnownError, "(resolve) wrong choise: #{choise}"
		end
		@f_broken = false
		define_d
		update
	end
	def pretty_print_instance_variables
		[:path, :@d]
	end
end
																																							#~ Tree::File/
																																							#~ Tree::File/




class Chunk
	::Chunks = self
	include Helpers

	#- for class
	class << self
		def set_db(db)
			@@db = db
			@@chunk_by_key = {}
		end
		
		# Chunk[key]
		# << chunk | nil if no such chunk
		def [](key)
			if d=@@db[key]
				@@chunk_by_key[key] ||= self.new key, d
			end
		end
		
		def create(key)
			@@db[key] = {}
		end
		def delete(key)
			@@db.delete key
			@@chunk_by_key.delete key
		end
		
		def save
			#. *sorting needed for tests to compare results (after adding processing in threads)
			@@db.replace @@db.sort.to_h if DirDB.dev?
			@@db.save
		end
	end

	def initialize(key, d)
		@key = key
		@d = d
		@files = Set.new @d.files
	end
																																							#~ Chunk
	def files
		@d.files
	end

	def bind_file(path)
		@files << path
		@d.files = @files.to_a
		#. *sorting needed for tests to compare results (after adding processing in threads)
		@d.files.sort! if DirDB.dev?
		@d.delete :empty_since
	end
	def unbind_file(path)
		@files.delete path
		@d.files = @files.to_a
		@d.files.sort! if DirDB.dev?
		if @d.files.empty?
			@d.empty_since = {at:at}
		end
	end

	def update(d)
		@d.update d
	end

	def inspect
		"<#{self.class}: #{@key}, #{@d} >"
	end
end
																																							#~ Chunk/


# -filter
class Filter
	attr :rules
	def initialize(db:nil)
		@db = db
		@rules = []
	end

	def load
		for data in @db.filter.rules || []
			rule = set_rule **data
			for data2 in data.children || []
				data2.parent = rule
				set_rule **data2
			end
		end
		self
	end
	def reset
		@rules.clear
		self
	end
	# < rule
	def set_rule(o)
		Rule.new(**o).tap do |rule|
			@rules << rule unless rule.child?
		end
	end
	def save
		@db.filter.rules = @rules.map &:data
		@db.filter.save
	end
end
																																							#~ Filter/


class DirFilter
	def initialize(dir:nil)
		@dir = dir
		@rel = @dir.parent_tdir
	end

	def init
		active_rules   # cache
	end

	def excludes?(fname)
																																										#-#!_ o^active_rules
		f_excluded = false
		for rule in active_rules
			# check file
			if !f_excluded
				for pattern in rule.exclude_files
					# *File::FNM_EXTGLOB needed for {a,b,c} support
					# *File::FNM_DOTMATCH needed to match files starting with '.'
					if File.fnmatch(pattern, fname, File::FNM_EXTGLOB|File::FNM_DOTMATCH | File::FNM_DOTMATCH)
						f_excluded = true
					end
				end
			end
			if f_excluded
				for pattern in rule.include_files
					if File.fnmatch(pattern, fname)
						f_excluded = false
					end
				end
			end
			if !f_excluded
				for pattern in rule.exclude_files_post
					if File.fnmatch(pattern, fname)
						f_excluded = true
					end
				end
			end
		end
		f_excluded
	end
																																							#~ DirFilter
	def active_rules
		@active_rules ||= begin
			f_dir_was_excluded = @dir.excluded?
			f_dir_excluded = false
			rules_to_check = Sync.global_filter.rules + @dir.tree.sync.filter.rules + children_rules
			dir_rules = rules_to_check.select do |rule|
				path =
					if rule.base_dir
						@dir.relative_path_from(rule.base_dir).to_s
					else
						@dir.path
					end
				if rule.dir_names
					if rule.dir_names.include? @dir.name
						next true
					end
				end

				if rule.dir_paths
					if rule.dir_paths.include? path
						next true
					end
				end

				if rule.dir_name_masks
					f_matched = rule.dir_name_masks.any? do |pattern|
						pattern.string? \
							? (File.fnmatch(pattern, @dir.name, File::FNM_DOTMATCH))
							: pattern.match(@dir.name)
					end
					if f_matched
						next true
					end
				end

				if rule.dir_path_masks
					# *File::FNM_PATHNAME — wildcard doesn't match '/'
					#  so in case of '.git/modules/*' — it will match only the module dir and not its subdirs
					f_matched = rule.dir_path_masks.any? do |pattern|
						pattern.string? \
							? (File.fnmatch(pattern, path, File::FNM_PATHNAME | File::FNM_DOTMATCH))
							: pattern.match(path)
					end
					if f_matched
						next true
					end
				end

				false
			end

			# add child rules if there is '.'
			for rule in dir_rules
				for child_rule in rule.children
					if child_rule.dir_names&.include?('.') || child_rule.dir_paths&.include?('.')
						dir_rules << child_rule
					end
				end
			end
			active_rules = inherited_rules + dir_rules
			active_rules.sort_by! &:n
			# do not add this dir if exclude branch detected
			active_rules.last.and.then do |_|
				# * here '*' is not the same as '*.*' because latter will skip files w/o extension
				if _.exclude_files == ['*'] && _.include_files.empty? && _.with_subdirs?
					f_dir_excluded = true
				end
			end
			if f_dir_excluded && !f_dir_was_excluded
				@dir.exclude
			elsif !f_dir_excluded && f_dir_was_excluded
				@dir.unexclude
			end
			active_rules
		end
	end

	def inherited_rules
		@inherited_rules ||= begin
			@rel \
				? (@rel.filter.active_rules.select &:with_subdirs?)
				: []
		end
	end

	def children_rules
		@children_rules ||= begin
			if @rel
				passed_children_rules = @rel.filter.children_rules
				rel_rules = @rel.filter.active_rules - @rel.filter.inherited_rules
				new_children_rules = rel_rules.sum([]) {|_| _.children || [] }
				# *.clone needed to have same rule with different base dirs
				new_children_rules = new_children_rules.map {|rule| rule.clone.set_base_dir(@rel) }
				# *uniq not needed here
				passed_children_rules + new_children_rules
			else
				[]
			end
		end
	end
end
																																							#~ DirFilter/


class Rule
	@@last_n = 0

	attr :n, :dir_names, :dir_paths, :dir_name_masks, :dir_path_masks, :include_files, :exclude_files, :exclude_files_post, :children, :base_dir
	# *we cannot recognize mask because "sdf[abc]{a,b,c}" is a valid folder name
	# *params order is important: include_files then exclude_files = exclude_files_post
	def initialize(o)
		raise KnownError, "(filters) should be - exclude_files: [...]" if o.exclude_file
		raise KnownError, "(filters) should be - include_files: [...]" if o.include_file
		@data = o
		_ = o
		@parent = _[:parent]
		@subdirs = _[:subdirs]
		@exclude_files = _[:exclude_files]
		@include_files = _[:include_files]
		@only_files = _[:only_files]

		# detect exclude_files_post
		if @include_files && @exclude_files && o.keys.index(:include_files) < o.keys.index(:exclude_files)
			@exclude_files_post = @exclude_files
			@exclude_files = []
		end

		@n = @@last_n += 1

		# prepare: @dir_names, @dir_paths, @dir_name_masks, @dir_path_masks
		# ensure names/paths array^dir_name
		@dir_names =
			if o.dir_names
				if o.dir_names.array?
					o.dir_names
				else
					raise KnownError, "(filters) dir_names: should be array"
				end
			else
				if o.dir_name
					if o.dir_name.string? || o.dir_name.regexp?
						[o.dir_name]
					else
						raise KnownError, "(filters) dir_name: should be a string or regexp"
					end
				else
					nil
				end
			end
		# ensure names/paths array^dir_path
		@dir_paths =
			if o.dir_paths
				if o.dir_paths.array?
					o.dir_paths
				else
					raise KnownError, "(filters) dir_paths: should be array"
				end
			else
				if o.dir_path
					if o.dir_path.string? || o.dir_path.regexp?
						[o.dir_path]
					else
						raise KnownError, "(filters) dir_path: should be a string or regexp"
					end
				else
					nil
				end
			end
		# ensure names/paths array^dir_name_mask
		@dir_name_masks =
			if o.dir_name_masks
				if o.dir_name_masks.array?
					o.dir_name_masks
				else
					raise KnownError, "(filters) dir_name_masks: should be array"
				end
			else
				if o.dir_name_mask
					if o.dir_name_mask.string? || o.dir_name_mask.regexp?
						[o.dir_name_mask]
					else
						raise KnownError, "(filters) dir_name_mask: should be a string or regexp"
					end
				else
					nil
				end
			end
		# ensure names/paths array^dir_path_mask
		@dir_path_masks =
			if o.dir_path_masks
				if o.dir_path_masks.array?
					o.dir_path_masks
				else
					raise KnownError, "(filters) dir_path_masks: should be array"
				end
			else
				if o.dir_path_mask
					if o.dir_path_mask.string? || o.dir_path_mask.regexp?
						[o.dir_path_mask]
					else
						raise KnownError, "(filters) dir_path_mask: should be a string or regexp"
					end
				else
					nil
				end
			end

		[@dir_names, @dir_paths, @dir_name_masks, @dir_path_masks].tap do |arr|
			raise KnownError, "(filters) rule error: At least one of these needed: dir_name[s], dir_path[s], dir_name_mask[s], dir_path_mask[s]" if arr.all? {|_| _.is.empty? }
		end

		# check vals
		for arr in [@dir_names, @dir_paths]
			for val in arr || []
				raise KnownError, "(filters) rule error: '#{val}' - should be exact name, not a mask:" if val.regexp? || val.includes?('*') || val.includes?('?')
			end
		end

		if @only_files
			@exclude_files = '*'
			@include_files = @only_files
		end

		# ensure array^@exclude_files
		@exclude_files = [@exclude_files] if @exclude_files.string?
		@exclude_files ||= []
		# ensure array^@include_files
		@include_files = [@include_files] if @include_files.string?
		@include_files ||= []
		# ensure array^@exclude_files_post
		@exclude_files_post = [@exclude_files_post] if @exclude_files_post.string?
		@exclude_files_post ||= []

		@children = []
		@parent.and.add_child self
	end
	def set_child_rule(o)
		Rule.new(
			parent:self,
			**o
		)
	end
	def with_subdirs?
		@subdirs
	end
	def child?
		@parent
	end
	def add_child(rule)
		@children << rule
	end
	def set_base_dir(base_dir)
		@base_dir = base_dir
		self
	end
	# (>>>)
	def data
		@data.except(:parent).tap do |h|
			if @children[0]
				h.children = @children.map &:data	# (>>>)
			end
		end
	end
end
																																							#~ Rule/



class StorageHelper
	# *@sync — can be Sync class or Sync instance
	def initialize(sync:nil)
		@sync = sync
		@db = @sync.db.storages
	end

	def storages
		@storages ||= begin
			require_relative 'Storage/_Storage'
			map = {}
			@db.each do |key, o|
				if o.only_for
					o.only_for = [o.only_for].flatten
					unless o.only_for.includes? Sync.device
						next
					end
				end

				if o.skip_for
					o.skip_for = [o.skip_for].flatten
					if o.skip_for.includes? Sync.device
						next
					end
				end

				map[key] = Storage[key].new **o.merge(key:key, sync_db:@sync.db)
			end
			raise NoDefinedStoragesError, '(storages) there are no defined storages' if map.empty?
																																										w("using storages: #{map.keys} (#{map.length}/#{@db.length})")
																																										w("rejected storages: #{@db.keys - map.keys}")
			map
		end
	end

	# storage by key
	# from = @sync.h_storage[:LocalFS]
	def [](key)
		storages[key]
	end

	def set(conf)
		use conf
		@db.save
	end

	# *db not saved
	def use(conf)
		@db.replace conf
	end

	# *if tokens missed — auth needed, so it is better to do it before any other operations and do it not in parallel for clear workflow
	#   otherwise .fast_one will fail with a timeout error
	def prepare
		storages.each do |key, storage|
			# *storages like LocalFS will be skipped
			# *if we have dir_id, usually it means that we already have tokens, so do not do anything here to do not slowdown operation with one-by-one storage init
			if storage.db && !storage.db.dir_id
				# *will cause auth if token missed
																																										w("[prepare #{key}]")
				storage.storage_dir
			end
		end
	end

	def for_each
		# in parallel threads
		storages.map do |key, storage|
			Thread.new do
				yield storage, key
																																										w("[> #{key} done]")
			end
		end.each &:join
	end

	def fast_one
		@fast_one ||= begin
																																										# time_start
																																										_time_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
			tmp_dir = (@sync.start_dir/:z_tmp_fast_one).create
			arr = []
			n = 0
			require 'timeout'
			Timeout.timeout 10 do
				for_each do |some_storage, key|
					# download base.dat as tmp file
					file = tmp_dir/"test_#{key}.tmp"
					some_storage.get 'base.dat', to:file
					data = eval(file.read) rescue {}
					data.storage = some_storage
					data.n = n += 1
					arr << data
					file.del!

				rescue Errno::ENOENT, KnownError
																																										w("(#{key}) error: #$!")
					# *do not use storage if base.dat is missed there
					:skip
				end

				raise KnownError, '(fast_one) error: all storages skipped (base.dat missed)' if arr.empty?
			end
			# get the fastest of storages with the latest data
			arr
				.sort_by {|_| [-_.last_up_at, _.n] }
				.first.storage
					.tap do |_|
						:log
																																										w("fast_one storage: #{_.key}")
																																										# time_end2^fast_one
																																										ttime = Process.clock_gettime(Process::CLOCK_MONOTONIC) - _time_start   # total time
																																										w("(fast_one) processed in #{'%.3f' % ttime}")
					end
		ensure
			tmp_dir&.del!
		end
	end
end



Shared = {}

# Error^KnownError < StandardError
class KnownError < StandardError;end
	# Error^MissedLinkError < KnownError
	class MissedLinkError < KnownError;end
	# Error^NoDefinedStoragesError < KnownError
	class NoDefinedStoragesError < KnownError;end
	# Error^WinPathLimitError < KnownError
	class WinPathLimitError < KnownError;end






