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
						found_file.mtime == file.mtime
					end
				end
			del_files =
				files[to].reject do |file|
					# skip if such file should exist
					files[from].find_by(name:file.name)
				end
			# *delete first to free up storage and to define a storage_dir
			to.del_many del_files
		
			tmp_dir = IDir.new(:z_tmp_sync).create   # dir is usually created in the project local dir
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
	def initialize(key:nil, sync_db:nil, **o)
		@key = key
		fail 'NotImplemented'
	end

	def mode
		Shared.mode || :up
	end

	# api stub
	def add_update(file)
		fail 'NotImplemented'
	end
	def add_update_many(files)
		do_in_parallel(tasks:files) do |file|
			add_update file
			print '.'
		end
	end

	def get(name, to:nil)
		to_file = to.is_a?(IDir) ? to/name : IFile.new(to)
		fail 'NotImplemented'
		to_file
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

	# all stored files
	def files
		fail 'NotImplemented'
	end

	def storage_dir
		fail 'NotImplemented'
	end

	def del_storage_dir!
		fail 'NotImplemented'
	end

	def do_in_parallel(tasks:nil)
		storage_dir   # ensure dir created here, not in each thread
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



#! should be is separate file
class Storage::LocalFS < Storage
	def initialize(key:nil, dir_path:nil, **o)
		@key = key
		@dir_path = dir_path
	end

	def add_update(file)
		file.copy_to storage_dir
	end
	def add_update_many(files)
		# *not in parallel
		files.each do |_|
			add_update _
			print '.'
		end
	end

	def get(name, to:nil)
		to_file = to.is_a?(IDir) ? to/name : IFile.new(to)
		file = storage_dir/name
		file >> to_file
		to_file
	end

	def del(name)
		storage_dir.files
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

	def files
		storage_dir.files
	end

	def storage_dir
		@storage_dir = IDir.new(@dir_path).create
	end

	def del_storage_dir!
		storage_dir.del!
		@storage_dir = nil
	end
end



#! should be is separate file
class Storage::GoogleDrive < Storage
	C_warn_dir_name = '! ! ! do not change the content here manually ! ! !'
	# credentials for PROD — https://console.cloud.google.com/apis/credentials?project=fardrive-318206
	# can be already defined in tests
	C_client_id ||= '1062295892893-hvgn9if8pl62g8kkcg1ji1kvjogm4omq.apps.googleusercontent.com'
	C_client_secret ||= 'njfZb-5r9M7hbxRhHylWyxCo'

	def initialize(key:nil, account:nil, sync_db:nil, dir_name:C_storage_dir_name, **o)
		@key = key
		@account = account
		@dir_name = dir_name
		raise KnownError, "(GoogleDrive) 'account' param missed" if !@account
		# *takes 1.5s
		require 'google_drive'
		key = "storage_GoogleDrive__#{@account}"
		@db = sync_db.storages_data[key] ||= {}
		sync_db.add_save!(@db, 'storages_data')
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
		if stored_file=storage_dir.file_by_title(file.name)
			stored_file.update_from_file file.abs_path
		else
			# *allows to upload files with the same name
			# upload_from_io(io, title = 'Untitled', params = {})
			storage_dir.upload_from_file(file.abs_path, nil, convert:false)
		end
	end

	def get(name, to:nil)
		to_file = to.is_a?(IDir) ? to/name : IFile.new(to)
		file = storage_dir.file_by_title name
		raise KnownError, "(GoogleDrive - #{@account}) file not found: #{name}" if !file
		file.download_to_file to_file.to_s
		to_file
	end

	def del(name)
		file = storage_dir.file_by_title name
		file.and.delete 'permanent'
	end

	def storage_dir
		@_storage_dir ||= begin
			if id=@db.dir_id
				session.folder_by_id id
			else
				# *session.collection_by_title — throws error because tries to work with the root dirs (no permission)
				# this file_by_title actually finds the dir
				dir = session.file_by_title @dir_name
				# (<!) raise if such dir already exists (may be used by other sync)
				# *for .down use a dir found by name
				if mode == :up
					raise KnownError, "(GoogleDrive - #{@account}) dir '#{@dir_name}' already exists -- provide other dir_name or delete this dir (even from Trash)" if dir
					dir = create_dir @dir_name

					# *add dir with a warn tittle ("warn-dir")
					#   there is a problem that if we upload some files to this dir manually (like via web UI) this app cannot see/access them because they
					#   are not created with the app; also we cannot clear/delete this dir, there will be an error;
					#     appNotAuthorizedToChild: The user has not granted the app 525741267076 write access to the child file 1RjqzReTiTwV-riDq8Eged05YVzArrY5v, which would be affected by the operation on the parent. (Google::Apis::ClientError)
					dir.create_subcollection C_warn_dir_name
				end

				@db.dir_id = dir.id
				@db.save
				dir
			end
		rescue Google::Apis::ClientError
			# if the dir missed — recreate
			if $!.status_code == 404
				if mode == :up
																																											w("storage_dir missed -- recreate")
					@db.delete :dir_id
					retry
				else
					raise KnownError, "(GoogleDrive - #{@account}) dir '#{@dir_name}' with id '#{id}' is missed"
				end
			else
				raise
			end
		end
	end

	def files
		storage_dir.files
			.reject {|_| _.name == C_warn_dir_name }
			.each {|_| _.extend FileExt }
	end

	def create_dir(name)
		session.create_collection name
	end

	def del_storage_dir!
		if dir=session.file_by_title(@dir_name)
			dir.delete 'permanent'
			@_storage_dir = nil
		end
	end

	# normalize file api
	module FileExt
		# ! this mtime is not a desktop time, but the uploading time (seems the dtop time is not stored on the cloud)
		def mtime
			modified_time
		end
	end
end



