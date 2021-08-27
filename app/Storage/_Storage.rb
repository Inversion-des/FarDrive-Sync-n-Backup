# FarDrive Sync&Backup
# Copyright © 2021 Yura Babak (yura.des@gmail.com, https://www.facebook.com/yura.babak, https://www.linkedin.com/in/yuriybabak)
# License: GNU GPL v3.0 (https://www.gnu.org/licenses/gpl-3.0.html)

class Storage
	C_storage_dir_name ||= 'FarDrive_storage'   # can be already defined in tests
	C_input_mutex = Mutex.new

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
			raise NameError, "#{name} class not found in #{self}"
		end
		
		# Storage.sync(from:, to:)
		def sync(from:nil, to:nil)
			# get files in parallel
			files = {}
			[from, to].map do |storage|
				Thread.new do
					files[storage] = storage.files
				end
			end.each &:join
		
			add_files =
				files[from].reject do |file|
					# skip if such file exists
					if found_file=files[to].find_by(name:file.name)
						#. *on clouds mtime is not the original so we cannot rely on it
						#  maybe we should have some mtime_preserved flag for storage
						# found_file.mtime == file.mtime
						# *risky: what if content is different?
						found_file.size == file.size
					end
				end
			del_files =
				files[to].reject do |file|
					# skip if such file should exist
					files[from].find_by(name:file.name)
				end
			# *delete first to free up storage and to define a storage_dir, set_dir
			to.del_many del_files
		
			# *'z_tmp_sync' added to Shared.skip_root_nodes
			# *we do not use tmp files if reading from LocalFS
			tmp_dir = from.is_a?(LocalFS) ? nil : IDir.new(:z_tmp_sync).create   # dir is usually created in the project local dir
			from.do_in_parallel(tasks:add_files) do |add_file|
				file = from.get(add_file.name, to:tmp_dir)
				to.add_update file
				print '.'
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
	def add_update(file)
		with_long_call_warns title:"add_update - #{file.name}" do
			yield
		end
	end

	def add_update_many(files)
		do_in_parallel(tasks:files) do |file|
			add_update file
			print '.'
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
		do_in_parallel(tasks:files) do |file|
			del file.name
			print '.'
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
end

	# + normalize file api (see in Storage::GoogleDrive)


#! should be is separate file
class Storage::LocalFS < Storage
	def initialize(key:nil, dir_path:nil, set:nil, **o)
		@key = key
		@dir_path = dir_path
		@set = set
		super
	end

	def add_update(file)
		super do
			file.copy_to target_dir
		end
	end
	def add_update_many(files)
		# *not in parallel
		files.each do |_|
			add_update _
			print '.'
		end
	end

	# *return ori file if to: not provided (optimization to avoid creating temp files)
	def get(name, to:nil)
		super do |to_file|
			file = target_dir/name
			if to
				file >> to_file
				to_file
			else
				file
			end
		end
	end

	def del(name)
		target_dir.files
			.find {|_| _.name == name }
			.then {|_| _.del! }
	end
	def del_many(files)
		# *not in parallel
		files.each do |_|
			del _.name
			print '.'
		end
	end

	def nodes(only_files:nil)
		if only_files
			target_dir.files
		else
			target_dir.children
		end
	end

	def storage_dir
		@storage_dir ||= IDir.new(@dir_path).create
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
end



#! should be is separate file
class Storage::GoogleDrive < Storage
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
				redirect_uri: "urn:ietf:wg:oauth:2.0\:oob",
				additional_parameters: {access_type:'offline'},
				state: 'gcd'   # *maybe helps to get rid of an additional step (works not for all)
			)

			begin
				# reuse token if saved
				if token=@db_global.refresh_token
					credentials.refresh_token = token
				else
					# get auth code in browser
					C_input_mutex.synchronize do
						auth_url = credentials.authorization_uri
						IO.popen('clip', 'w') {|_| _.write auth_url.to_s }
						puts "\n1) Open this page in your browser for [[ #{@account} ]] account (URL ALREADY COPIED to clipboard):\n  #{auth_url}"
						print '2) When auth done -- copy the received code to clipboard and JUST HIT ENTER here:'
						((( $stdin.gets )))
						authorization_code = `powershell get-clipboard`.chomp
						puts "  #{authorization_code}"
						credentials.code = authorization_code
					end
				end

				credentials.fetch_access_token!

			rescue Signet::AuthorizationError
				if $!.message.includes? 'Token has been expired or revoked'
					@db_global.refresh_token = nil
					retry
				else
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

	def add_update(file)
		super do
			if stored_file=target_dir.file_by_title(file.name)
				stored_file.update_from_file file.abs_path
			else
				# *allows to upload files with the same name
				# upload_from_io(io, title = 'Untitled', params = {})
				target_dir.upload_from_file(file.abs_path, nil, convert:false)
			end
		# *too many different errors: HTTPClient::KeepAliveDisconnected, Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::ENETUNREACH, Google::Apis::TransmissionError, SocketError
		rescue
			attempt ||= 0
			attempt += 1
			# retry for 1 hour
			if attempt <= 360
				sleep 10
				# *log error type
				print "[add_update retry - #{$!.inspect}]"
				retry
			end
			raise
		end
	end

	def get(name, to:nil)
		super do |to_file|
			file = target_dir.file_by_title name
			raise KnownError, "(GoogleDrive - #{@account}) file not found: #{name}" if !file
			# *attempt with acknowledge_abuse needed to allows downloading of files infected with a virus
			#  otherwise service will return Invalid request (Google::Apis::ClientError) with Forbidden in details
			#  https://github.com/gimite/google-drive-ruby/issues/413
			begin
				file.download_to_file to_file.to_s
			rescue Google::Apis::ClientError
				print "[get retry for '#{name}' - #{$!}]"
				file.download_to_file to_file.to_s, acknowledge_abuse:true
			end
			to_file
		end
	end

	def del(name)
		file = target_dir.file_by_title name
		file.and.delete 'permanent'
	end

	def storage_dir
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
					raise KnownError, "(GoogleDrive - #{@account}) dir '#{@dir_name}' is missed"
				end
			end

			dir
		end
	end

	def set_dir
		@set_dir ||= begin
			storage_dir.subcollection_by_title(@set) || storage_dir.create_subcollection(@set)
		end
	end

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




