# FarDrive Sync&Backup
# Copyright © 2021 Yura Babak (yura.des@gmail.com, https://www.facebook.com/yura.babak, https://www.linkedin.com/in/yuriybabak)
# License: GNU GPL v3.0 (https://www.gnu.org/licenses/gpl-3.0.html)

class StorageArray
	C_special_files = ['base.dat', '#set_db.7z']

	attr :key, :db
	attr_accessor :base_data
	def initialize(key:nil, set:nil, db:nil)
		@key = key
		@set = set
		@db = db
		@set ||= Sync::C_def_set_name
		@db._config ||= {}
		@mutex = Mutex.new
	end

	def storage_dir
		for_each do |storages|
			storages.storage_dir
		end
	end

	# < true if this is true for some storage (checks in parallel)
	def set_dir_exists?
		res = false
		for_each do |storage|
			res ||= storage.set_dir_exists?
		end
		res
	end

	def for_each
		# in parallel threads
		storagesH.map do |key, storage|
			Thread.new do
				yield storage, key
			end
		end.each &:join
	end

	def get(name, to:nil)
		if storage=storage_by(name)
			storage.get(name, to:to)
		else
			if name.in? C_special_files
				# try to get that file from all the storages in parallel
				file = nil
				threads = []
				storages.map do |storage|
					threads << Thread.new do
						file ||= storage.get(name, to:to)
						threads.each &:kill
					rescue Storage::FileNotFound
						:ignore
					end
				end
				threads.each &:join

				file || raise(FileNotFound, name)
			else
				raise FileNotFound, name
			end
		end
	rescue Storage::FileNotFound
		# wrong special file location
		if name.in? C_special_files
																																										w("wfrong special file location: #{files_map[name]}")
			# *this will cause getting from other storages
			files_map.delete name
			retry
		else
			raise FileNotFound, name
		end
	end
																																							#~ StorageArray
	def add_update(file)
		# *do not allow to add in parallel, because storage selection is based on free space (so it should be updated after each upload)
		@mutex.sync do
			fn = file.name
			# select storages
			possible_storages = []
			if storage=storage_by(fn)   # if file update
				free_space = storage.free_space + files_map[fn].size
				if free_space > file.size
					possible_storages << storage
				else
					file_old_storage = storage
				end
			end
			# some files try to store on the first storage in the list
			if fn.in? C_special_files
				possible_storages << storages.first
			end
			possible_storages += storages_queue.select {|_| _.free_space > file.size }
			possible_storages.uniq!
			# upload attempts
			begin
				if storage=possible_storages.shift
																																										w("  (array) add_update to: #{storage.key}")
					storage.add_update file
					# *update works thanks to hash default proc
					files_map[fn].update(
						storage: storage.key.to_s,
						# *7z creates files with slightly different size and it breaks compare_packs!
						#  so here we round size (-1 is not enough)
						size: (DirDB.dev? && fn.end_with?('.7z')) ? file.size.round(-2) : file.size
					)
					storage.update_stats
				else
					raise NoFreeSpace
				end
			rescue Storage::NoFreeSpace
				retry  # use next storage
			end

			# -- file uploaded --

			file_old_storage.and.then do |_|
				_.del fn
				_.update_stats
			end
		end
	end
																																							#_ StorageArray
	def storage_by(fname)
		storagesH[ files_map[fname]&.storage ]
	end

	def files_map
		@mutex.sync_if_needed do
			# "1_2021.08.08"=>{storage:'GoogleDrive_1', size:777}
			@files_map ||= begin
				map = Hash.new {|h, k| h[k]={}.extend(FileDataExt) }
				if h=@db._files_map
					h.each do |k, v|
						map[k] = v.extend(FileDataExt)
					end
				else
																																										w("files_map -- auto-discovery")
					# initial map discovery
					storages.each do |storage|
						storage.files.each do |_|
							map[_.name].update(
								storage: storage.key.to_s,
								size:_.size
							)
						end
					end
				end
				@db._files_map = map
			end
		end
	end

	def storages_queue
		@strategy ||= @db._config.strategy || 'even'
		# _config: {strategy:'one_by_one', order: [:LocalFS, :LocalFS_2] }
		if @strategy == 'one_by_one'
			order = @db._config.order || raise(KnownError, "'order' param missed in the _config for #{@key}")
			storages.sort_by {|_| order.index(_.key) || raise(KnownError, "#{_.key} not found in the 'order' list") }
		else   # even (default, get less used first)
			storages.sort_by {|_| [_.used_space, storages.index(_)] }
		end
	end
																																							#~ StorageArray
	def storages
		storagesH.values
	end
	def storagesH
		# *can be already locked by .files_map
		@mutex.sync_if_needed do
			@storagesH ||= begin
				map = {}
				@db.each do |key, o|
					next if key[0] == '_'   # skip '_config', '_files_map'
					map[key] = Storage[key].new(**o.merge(key:key, set:@set)).extend(StorageExt).tap{|_| _.array = self; _.db = o }
				end
				map
			end
		end
	end

	# if over_used_space — move some files to other storages
	def balance_if_needed(tmp_dir:nil, h_storage:nil)
		storages.each do |storage|
			while storage.used_space > storage.quota
				over_used_space = storage.used_space - storage.quota
																																										w(%Q{over_used_space.hr=}+over_used_space.hr.inspect)
																																										w(%Q{  storage.key=}+  storage.key.inspect)
				# find the best file_to_move
				file_name_to_move = nil
				moved_file_size = nil
				min_size_diff = storage.used_space + 1
				files_map.each do |some_file_name, some_file_d|
					next if some_file_d.storage != storage.key # we need only files on this storage
					size_diff = (some_file_d.size - over_used_space).abs
					if size_diff < min_size_diff
						min_size_diff = size_diff
						file_name_to_move = some_file_name
						moved_file_size = some_file_d.size
					end
				end
				 																																						w(%Q{  file_name_to_move=}+  file_name_to_move.inspect)
																																										w(%Q{  moved_file_size.hr=}+  moved_file_size.hr.inspect)
				# *fast_one used here to do not download file from cloud if it is available on LocalFS
				from = h_storage.and.fast_one || storage_by(file_name_to_move)
				# *we do not use tmp file if reading from LocalFS
				to = from.is_a?(Storage::LocalFS) ? nil : tmp_dir
				file_to_move = from.get file_name_to_move, to:to
				# *it should find the best next storage and delete from the current one
				add_update file_to_move

				# delete tmp file
				file_to_move.del! if to
			end
		end
	end

	def nodes(only_files:nil)
		mutex = Mutex.new
		nodes = []
		for_each do |storage|
			res = storage.nodes(only_files:only_files)
			mutex.sync do
				nodes += res
			end
		end
		nodes
	end
	def files
		nodes only_files:true
	end

	def del(name)
		if storage=storage_by(name)
			storage.del name
			files_map.delete name
		end
	end
	def del_many(files)
		by_storage = Hash.new {|h, k| h[k]=[] }
		for file in files
			if storage_key=files_map[file.name]&.storage
				by_storage[storage_key] << file
			end
		end
		for storage_key, files in by_storage
			storagesH[storage_key].del_many files
			files_map.delete_keys! files.map(&:name)
		end
	end

#	# *can be used for get, but inside .add_update we block parallel uploads
#	# *copy from Storage
#	def do_in_parallel(tasks:)
#		for_each do
#			~storages.target_dir   # ensure dir created here, not in each thread
#
#		tasks = tasks.dup
#		5.times.map do
#			Thread.new do
#				while task=tasks.shift
#					yield task
#		end.each &:join


	module StorageExt
		attr_accessor :db, :array
		def quota
			@db.quota_GB.and.GB || @db.quota_MB.and.MB || Float::INFINITY
		end
		def used_space
			@db.used || (update_stats; @db.used)
		end
		def free_space
			quota - used_space
		end
		def update_stats
			@db.used = @array.files_map.values.sum{|_| _.storage == @key ? _.size : 0 }
			@db.used_MB = (@db.used.to_f / 1.MB).ceil
			@db.used_perc = (@db.used.to_f / quota * 100).round(1) if quota < Float::INFINITY
		end
	end

	# *for hash like: {storage:'GoogleDrive_1', size:155}
	module FileDataExt
		def size
			self[:size]
		end
		def storage
			self[:storage]&.to_sym
		end
	end

	# Error^NoFreeSpace < KnownError
	class NoFreeSpace < KnownError;end
	# Error^FileNotFound < KnownError
	class FileNotFound < KnownError;end
end

