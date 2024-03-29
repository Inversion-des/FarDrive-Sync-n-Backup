# FarDrive Sync&Backup
# Copyright © 2021 Yura Babak (yura.des@gmail.com, https://www.facebook.com/yura.babak, https://www.linkedin.com/in/yuriybabak)
# License: GNU GPL v3.0 (https://www.gnu.org/licenses/gpl-3.0.html)

class Storage
	C_storage_dir_name ||= 'FarDrive_storage'   # can be already defined in tests
	C_input_mutex = Mutex.new
	include MonitorMixin

	#- for class
	class << self
		# Storage[key].new
		def [](name)
			#. GoogleDrive_1 -> GoogleDrive
			name = name.to_s.sub /_\d+$/, ''
			#. allow to get only scoped classes, not any visible constant
			raise NameError unless self.constants.includes? name.to_sym
			self.const_get name
		rescue NameError
			raise NameError, "'#{name}' class not found in #{self}"
		end
		
		# Storage.sync(from:, to:)
		# from/to: Storage || StorageArray
		def sync(from:nil, to:nil)
			# get files in parallel
			files = {}
			Ticker['get files took'] do
				[from, to].map do |storage|
					Thread.new do
						files[storage] = storage.files
					end
				end.each &:join
			end
		
			progress = ProgressBar["- prepare add_files (check #{files[from].n} files)", total: files[from].n]
			add_files =
				files[from].reject do |file|
					# skip if such file exists
					res = if found_file=files[to].find_by(name:file.name)
						#. *on clouds mtime is not the original so we cannot rely on it
						#  maybe we should have some mtime_preserved flag for storage
						# found_file.mtime == file.mtime
		
						# *risky: what if content is different?
						# found_file.size == file.size
		
						# 19.09.22 trying to use checksum (found that GDrive supports this) — may be unsupported by other storages
						found_file.md5_checksum == file.md5_checksum
					end
					progress.inc
					res
				end
			add_files.sort_by! &:name
			progress = ProgressBar["- prepare del_files (check #{files[to].n} files)", total: files[to].n]
			del_files =
				files[to].reject do |file|
					# skip if such file should exist
					files[from].find_by(name:file.name).tap do
						progress.inc
					end
				end
			# *delete first to free up storage and to define a storage_dir, set_dir
			to.del_many del_files
		
			# *'z_tmp_sync' added to Shared.skip_root_nodes
			# *we do not use tmp files if reading from LocalFS
			tmp_dir = from.is_a?(LocalFS) ? nil : IDir.new(:z_tmp_sync).create   # dir is usually created in the project local dir
			progress = ProgressBar["- copy (#{add_files.n})", total: add_files.n]
			process_file = -> (add_file) do
				file = from.get(add_file.name, to:tmp_dir)
				to.add_update file
				progress.inc
			end
			if from.is_a? Storage
				from.do_in_parallel tasks:add_files, &process_file
			else   # not in parallel for StorageArray
				add_files.each &process_file
			end
		
			{add_files:add_files, del_files:del_files}
		ensure
			tmp_dir&.del!
		end
	end


	attr :key, :db
	attr_accessor :base_data
	def initialize(key:nil, set:nil, in_storage_dir:nil, **o)
		@key = key
		@set = set
		@in_storage_dir = in_storage_dir
		@set ||= Sync::C_def_set_name
	end

	def target_dir
		@target_dir ||= @in_storage_dir ? storage_dir : set_dir
	end
#	def target_dir=(dir)
#		@target_dir = dir
	# *used for migration
	def in_storage_dir
		@target_dir = storage_dir
		yield
		@target_dir = nil
	end

	def mode
		Shared.mode || :up
	end
	def with_long_call_warns(title:nil)
		# *log warn about long operation
		thread = Thread.new do
			sleep 20.mins
			print "[#{title} took 20 mins]"
			sleep 20.mins
			print "[#{title} took 40 mins]"
		end
		yield
	ensure
		thread.kill
	end

	#-- api stubs
	def add_update(file, shared_line=nil)
		with_long_call_warns title:"add_update - #{file.name}" do
			yield
		end
	end

	def add_update_many(files, part=nil)
		done_n = 0
		do_in_parallel(tasks:files) do |file|
			add_update file
			if part
				done_n += 1
				part.close('.' * done_n)
			else
				print '.'
			end
		end
	end

	def get(name, to:nil)
		with_long_call_warns title:"get - #{name}" do
			# *to can be nil for example in LocalFS, where we just return the ori file and do not copy it to the temp 'to' file (to_file is not used in that case)
			if to
				to_file = to.is_a?(IDir) ? to/name : IFile.new(to)
			end
			yield to_file
		end
	end

	def get_many(names, to_dir:nil)
		do_in_parallel(tasks:names) do |name|
			get(name, to:to_dir)
			print '.'
		end
	end

	def del(name)
		fail 'NotImplemented'
	end
	def del_many(files)
		progress = ProgressBar["- del_many (#{files.n})", total:files.n]
		do_in_parallel(tasks:files) do |file|
			del file.name
			progress.inc
		end
	end

	def nodes(only_files:nil)
		fail 'NotImplemented'
	end
	# all stored files
	def files
		nodes only_files:true
	end

	def storage_dir
		fail 'NotImplemented'
	end

	def set_dir
		fail 'NotImplemented'
	end

	# do not create, just check
	def set_dir_exists?
		fail 'NotImplemented'
	end

	def del_storage_dir!
		@storage_dir = nil
		@target_dir = nil
	end

	def do_in_parallel(tasks:nil)
		target_dir   # ensure dir created here, not in each thread
		tasks = tasks.dup
		5.times.map do
			Thread.new do
				while task=tasks.shift
					yield task
				end
			end
		end.each &:join
	end

	# + normalize file api (see in Storage::GoogleDrive)

	# Error^NoFreeSpace < KnownError
	class NoFreeSpace < KnownError;end
	# Error^FileNotFound < KnownError
	class FileNotFound < KnownError;end
end



#! should be is separate file
class Storage::LocalFS < Storage
																																							#~ LocalFS\
	def initialize(key:nil, dir_path:nil, set:nil, **o)
		@key = key
		@dir_path = dir_path
		@set = set
		super
	end

	def add_update(file, shared_line=nil)
		super do
			# (<!) skip if file already exists
			target_file = target_dir/file.name
			if target_file.exists? && file.same_as(target_file, by: :checksum)
				w "(add_update) target_file already exists: #{target_file} -- skipping"
				return
			end

			file.copy_to target_dir
		end
	end
	def add_update_many(files, part=nil)
		done_n = 0
		# *not in parallel
		files.each do |_|
			add_update _
			if part
				done_n += 1
				part.close('.' * done_n)
			else
				print '.'
			end
		end
	end

	# *return ori file if to: not provided (optimization to avoid creating temp files)
	def get(name, to:nil)
		super do |to_file|
			file = target_dir/name
			raise FileNotFound, "(#{@key}) file not found: #{name}" if !file.exists?
			if to
				file >> to_file
				to_file
			else
				file
			end
		end
	end
																																							#~ LocalFS
	def del(name)
		target_dir.files
			.find {|_| _.name == name }
			.then {|_| _.del! }
	end
	def del_many(files)
		# *not in parallel
		progress = ProgressBar["- del_many (#{files.n})", total:files.n]
		files.each do |_|
			del _.name
			progress.inc
		end
	end

	def nodes(only_files:nil)
		if only_files
			target_dir.files.each do |_|
				_.extend IFileExt
				_.storage = self
			end
		else
			target_dir.children
		end
	end

	def storage_dir
		@storage_dir ||= IDir.new(@dir_path).create
	rescue Errno::ENOENT
		raise KnownError, "(#{@key}) storage_dir access failed: #$!"
	end

	def set_dir
		@set_dir ||= (storage_dir/@set).create
	end

	# do not create, just check
	def set_dir_exists?
		storage_dir[@set].exists?
	end

	def del_storage_dir!
		storage_dir.del!
		super
	end

	# *db is already used in Array
	def dir_db
		@dir_db ||= DirDB.new(dir:@target_dir, save_at_exit:1)
	end

	module IFileExt
		def storage=(storage)
			@storage = storage
		end

		# (mod) add cache
		def md5_checksum
			mtime_i = mtime.to_i
			# (<!) return cached md5 if available
			if d=@storage.dir_db.md5_cache[name]
				return d.md5 if d.mtime_i == mtime_i
			end
			# cache and return
			super.tap do |md5|
				@storage.dir_db.md5_cache[name] = {md5:md5, mtime_i:mtime_i}
			end
		end

		# (mod) rem cache
		def del!
			@storage.dir_db.md5_cache.delete name
			super
		end
	end
end

																																							#~ LocalFS/



#! should be is separate file
class Storage::GoogleDrive < Storage
																																							#~ GoogleDrive\
	C_warn_dir_name = '! ! ! do not change the content here manually ! ! !'
	# credentials for PROD — https://console.cloud.google.com/apis/credentials?project=fardrive-318206
	# can be already defined in tests
	C_client_id ||= '1062295892893-hvgn9if8pl62g8kkcg1ji1kvjogm4omq.apps.googleusercontent.com'
	C_client_secret ||= 'njfZb-5r9M7hbxRhHylWyxCo'

	def initialize(key:nil, account:nil, set:nil, dir_name:C_storage_dir_name, **o)
		@key = key
		@account = account
		@set = set
		@dir_name = dir_name
		super
		raise KnownError, "(GoogleDrive) 'account' param missed" if !@account
		# *takes 1.5s
		require 'google_drive'
		key = "storage_GoogleDrive__#{@account}"
		@db_global = Sync.db.storages_data[key] ||= {}
		Sync.db.add_save!(@db_global, 'storages_data')
	end

	def session
		@session ||= begin
			credentials = Google::Auth::UserRefreshCredentials.new(
				client_id: C_client_id,
				client_secret: C_client_secret,
				#. Drive API scopes — https://developers.google.com/drive/api/v3/about-auth
				#  we need only permission to create a dir and manage files inside that dir
				scope: ['https://www.googleapis.com/auth/drive.file'],
				redirect_uri: 'http://127.0.0.1:7117',
				additional_parameters: {access_type:'offline'},
				state: 'gcd'   # *maybe helps to get rid of an additional step (works not for all)
			)

			begin
				# reuse token if saved
				if token=@db_global.refresh_token
					credentials.refresh_token = token
				else
					# get auth code via browser
					C_input_mutex.sync do
						auth_url = credentials.authorization_uri
						# copy url to clipboard
						IO.popen('clip', 'w') {|_| _.write auth_url.to_s }
						# show msg
						putsn "\nOpen this page in your browser for [[ #{@account} ]] account (URL ALREADY COPIED to clipboard):\n  #{auth_url}"
						print 'Waiting for OAuth 2.0 authorization in the browser...'

						#-- run a simple server and wait for the callback
						require 'socket'
						thr = Thread.new do
							Socket.tcp_server_loop(7117) do |socket|
								get_line = socket.gets   # read the first line
								# http://127.0.0.1:7117/?code=4/0ARtbsJpOXYfLtrBw8Rlc2ByR…GkTXZ4mnjmJdcV_fVIs4Q&scope=https://www.googleapis.com/auth/drive.file
								# GET /?code=4/0ARtbsJpOXYfLtrBw8Rl…GkTXZ4mnjmJdcV_fVIs4Q&scope=https://www.googleapis.com/auth/drive.file HTTP/1.1
								credentials.code = get_line[/code=(.+?)&/, 1] || raise(KnownError, 'token not found')
								# response
								socket.puts "HTTP/1.1 200\r\n\r\n"
								socket.puts 'Received code: ' + credentials.code + "\nReturn to the app now.\nThis page can be closed."
							ensure
								socket.close
								thr.kill   # terminate the server
							end
						end
						trap('SIGINT') { thr.kill }
						((( thr.join )))
						puts 'done'
					end
				end

				credentials.fetch_access_token!

			rescue Signet::AuthorizationError
				if $!.message.includes? 'Token has been expired or revoked'
					@db_global.refresh_token = nil
					retry
				else
					# retry for 1 hour^session
					attempt ||= 0
					attempt += 1
					if attempt <= 360
						sleep 10
						# *log error type
						print "[session retry - #{$!.inspect}]"
						retry
					end
					raise
				end
			end

			# save/update refresh_token
			if credentials.refresh_token != @db_global.refresh_token
				if @db_global.refresh_token
					:token_updated
																																										w("NEW refresh_token")
				end
				@db_global.refresh_token = credentials.refresh_token
				@db_global.save
			end

			::GoogleDrive::Session.from_credentials credentials
		end
	end

	def add_update(file, shared_line=nil)
		super do
			if stored_file=target_dir.file_by_title(file.name)
				# (<!) skip if file already exists
				if file.md5_checksum == stored_file.md5_checksum
					w "(add_update) stored_file already exists: #{file} -- skipping"
					return
				end

				stored_file.update_from_file file.abs_path
			else
				# *allows to upload files with the same name
				# upload_from_io(io, title = 'Untitled', params = {})
				target_dir.upload_from_file(file.abs_path, nil, convert:false)
			end
		# *too many different errors: HTTPClient::KeepAliveDisconnected, Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::ENETUNREACH, Google::Apis::TransmissionError, SocketError
		rescue StandardError => e
			# (<!)
			if e.is_a?(Google::Apis::ClientError) && e.message.includes?('storageQuotaExceeded')
				raise NoFreeSpace
			end

			# retry for 1 hour^add_update
			attempt ||= 0
			attempt += 1
			if attempt <= 360
				sleep 10
				# *log error type
				print "[add_update retry - #{$!.inspect}]"
				retry
			end
			raise
		end
	end
																																							#~ GoogleDrive
	def get(name, to:nil)
		acknowledge_abuse = false

		# *to.is.empty? — cannot be used, because it returns true for empty dir
		raise KnownError, "(#{@key} - get) error: 'to' param is missed" if to.nil? || to == ''

		super do |to_file|
			file = target_dir.file_by_title name
			raise FileNotFound, "(#{@key}) file not found: #{name}" if !file
			# *attempt with acknowledge_abuse needed to allows downloading of files infected with a virus
			#  otherwise service will return Invalid request (Google::Apis::ClientError) with Forbidden in details
			#  https://github.com/gimite/google-drive-ruby/issues/413
			file.download_to_file to_file.to_s, acknowledge_abuse:acknowledge_abuse
			to_file
		# *too many different errors: Errno::ECONNRESET
		rescue StandardError => e
			case e
				when KnownError
					raise
				when Google::Apis::ClientError
					print "[get retry for '#{name}' - #{$!}]"
					acknowledge_abuse = true
					retry
				else
					# retry for 1 hour^get
					attempt ||= 0
					attempt += 1
					if attempt <= 360
						sleep 10
						# *log error type
						print "[get retry - #{$!.inspect}]"
						retry
					end
					raise
			end
		end
	end

	def del(name)
		file = target_dir.file_by_title name
		file.and.delete 'permanent'
	# *too many different errors:
	rescue StandardError => e
		# retry for 1 hour^del
		attempt ||= 0
		attempt += 1
		if attempt <= 360
			sleep 10
			# *log error type
			print "[del retry - #{$!.inspect}]"
			retry
		end
		raise
	end

	def storage_dir
		sync do
			@storage_dir ||= begin
				# *session.collection_by_title — throws error because tries to work with the root dirs (no permission)
				# this file_by_title actually finds the dir
				dir = session.file_by_title @dir_name
				if !dir
					if mode == :up   # default
						dir = create_dir @dir_name
						if @in_storage_dir
							# *add dir with a warn tittle ("warn-dir")
							#   there is a problem that if we upload some files to this dir manually (like via web UI) this app cannot see/access them because they
							#   are not created with the app; also we cannot clear/delete this dir, there will be an error;
							#     appNotAuthorizedToChild: The user has not granted the app 525741267076 write access to the child file 1RjqzReTiTwV-riDq8Eged05YVzArrY5v, which would be affected by the operation on the parent. (Google::Apis::ClientError)
							res = dir.create_subcollection C_warn_dir_name
						end
					else
						raise KnownError, "(#{@key}) dir '#{@dir_name}' is missed"
					end
				end

				dir
			end
		end
	end

	def set_dir
		sync do |_|
			@set_dir ||= begin
				storage_dir.subcollection_by_title(@set) || storage_dir.create_subcollection(@set)
			end
		end
	end
																																							#_ GoogleDrive
	# do not create, just check
	def set_dir_exists?
		storage_dir.subcollection_by_title(@set)
	end

	def nodes(only_files:nil)
		arr = []
		# *without block it returns only first 100 files
		o = {}
		if only_files
			o = {q:"mimeType != 'application/vnd.google-apps.folder'"}
		end
		target_dir.files(o) do |_|
			next if _.name == C_warn_dir_name
			arr << _.extend(FileExt)
		end
		arr
	end

	def create_dir(name)
		session.create_collection name
	end

	def del_storage_dir!
		if dir=session.file_by_title(@dir_name)
			dir.delete 'permanent'
		end
		super
	end

	# normalize file api
	module FileExt
		# ! this mtime is not a desktop time, but the uploading time (seems the dtop time is not stored on the cloud)
		def mtime
			modified_time
		end
		def move_to(dest)
			dest.add self
		end
	end
end
																																							#~ GoogleDrive/




