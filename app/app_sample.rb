# copy this file as app.rb and modify
# then run cmd in the main folder and use related commands from the comments below (marked with CMD:)
require_relative 'Sync'

class App
	def initialize
		# ------- main setup ---------------------

		# dir to backup (also in this file you can find "multiple dirs sample")
		@local_1 = 'D:/my_projects'

		# dir to restore on this or other machine
		@local_2 = 'D:/my_projects (restored)'

		# at least one storage should be defined
		@storages = {
			LocalFS: {
				dir_path: 'F:/FarDrive_storage',
				only_for: 'home_PC'
			},
			GoogleDrive_1: {
				account: 'yura.des@gmail.com'
			},
			GoogleDrive_2: {
				account: 'des7ign@gmail.com',
				skip_for: 'laptop'
			}
		}

		# ------- /main setup ---------------------
	end


	def cmd
		init
																																												# time_start
																																												_time_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
		# all the 'run' commands
		case $*[0]


			# sync UP (backup)
			# CMD: run -up
			when '-up'
				sync.up do
					sync.h_storage.set @storages
				end

			# sync DOWN (restore)
			# CMD: run -down
			when '-down'
				@local = @local_2
				sync.down do
					sync.h_storage.use @storages
				end



			# ------- ↓ next commands are optional  -------------------------------------------------------------------------------------


			# update project filter (.db/filter.dat)
			# CMD: run -update_filter
			when '-update_filter'
				sync.filter.reset

				sync.filter.set_rule(
					dir_paths: ['webserv/master', 'webserv/old_ver']
				).tap do |_|
					_.set_child_rule(
						dir_paths: [
							'.',
							'public',
							'public/css',
							'public/js',
						],
						exclude_files: ['.metadata_*.json', '*.log', 'w.txt']
					)
					_.set_child_rule(
						dir_paths: [
							'public/css/serv_dev',
							'public/css/serv_sources',
						],
						exclude_files: '*.css'
					)
					_.set_child_rule(
						dir_names: ['compiled', 'compiled_dev'],
						exclude_files: ['*.js', '*.css']
					)
				end

				# sync portable Sublime Text state
				sync.filter.set_rule(
					dir_path: 'Programs/Sublime Text'
				).tap do |_|
					_.set_child_rule(
						dir_paths: [
							'Data/Index',
							'Data/Cache',
						],
						subdirs: true,
						exclude_files: '*'
					)
					_.set_child_rule(
						dir_path: 'Data/Packages/User',
						exclude_files: ['AutoFoldCode.sublime-settings']
					)
				end

				sync.filter.save


			# update global filter (.db/filter.dat)
			# CMD: run -update_global_filter
			when '-update_global_filter'
				Sync.global_filter.reset
				Sync.global_filter.set_rule(
					dir_name: '.git'
				).tap do |_|
					_.set_child_rule(
						dir_name: '.',
						dir_path_mask: 'modules/*',
						exclude_files: ['gitk.cache', 'index', 'tortoisegit.data', 'tortoisegit.index']
					)
					_.set_child_rule(
						dir_name: 'logs',
						subdirs: true,
						exclude_files: '*'
					)
				end
				Sync.global_filter.set_rule(
					dir_name_mask: '*',
					exclude_files: '*.{BASE,LOCAL,REMOTE}.*'
				)
				Sync.global_filter.save


			# backup .db dir (global filter, storage tokens)
			# CMD: run -db_global_sync_up
			when '-db_global_sync_up'
				Sync.h_storage.set(
					LocalFS: {
						dir_path: 'F:/__FarDrive_db_global',
						only_for: 'home_PC'
					},
					GoogleDrive: {
						account: 'yura.des@gmail.com',
						dir_name: 'FarDrive_db_global (home_PC, laptop)'
					}
				)
				Sync.db_up


			# set uniq device ID (.db/base.dat)
			# *needed only to define custom storage maps for each device or change some paths
			# CMD: run -set_device_id home_PC
			when '-set_device_id'
				Sync.db.device.id = $*[1]
				Sync.db.device.save


			# define storages (.db/sets/#def_set/storages.dat)
			# CMD: run -set_storages
			when '-set_storages'

				if :simple
					# simple single storages sample
					sync.h_storage.set(
						LocalFS: {
							dir_path: 'F:/FarDrive_storage'
						},
						GoogleDrive: {
							account: 'yura.des@gmail.com'
						}
					)

				elsif !:arrays
					# 2 storage arrays sample
					sync.h_storage.set(
						array_1: {
							_config: {
								only_for: 'home_PC'
								# default strategy: even
							},
							LocalFS: {
								dir_path: 'F:/FarDrive_storage',
								quota_MB: 700
							},
							LocalFS_2(
								dir_path: 'G:/FarDrive_storage',
								quota_GB: 20
							)
						},
						array_2: {
							_config: {
								strategy: 'one_by_one',
								order: [:GoogleDrive_1, :GoogleDrive_2, :GoogleDrive_3],
								skip_for: 'nout'
							},
							GoogleDrive_1: {
								account: 'yura.des@gmail.com',
								quota_GB: 10
							},
							GoogleDrive_2: {
								account: 'other@gmail.com',
								quota_GB: 15
							},
							GoogleDrive_3: {
								account: 'third@gmail.com',
								quota_GB: 12
							}
						}
					)
				end


			# hepler to upload files to the new added storage (in case of GoogleDrive it is important that all the files are created by the app)
			# CMD: run -storage_sync
			when '-storage_sync'
				require_relative 'Storage/_Storage'

				sync.h_storage.use @storages

				Storage.sync(
					from: sync.h_storage[:LocalFS],
					to: sync.h_storage[:GoogleDrive_2]
				)

			else
				puts '! ! ! wrong cmd params'
		end
		 																																										# time_end^--- Total time: #{'%.3f' % ttime} (#{'%.1f' % (ttime.to_f / 60)} min) ---
		 																																										ttime = Process.clock_gettime(Process::CLOCK_MONOTONIC) - _time_start   # total time
		 																																										w("--- Total time: #{'%.3f' % ttime} (#{'%.1f' % (ttime.to_f / 60)} min) ---")
	end
	def init
		DirDB.prod!
		# $>.sync = true  # *realtime log (slower processing)
		Thread.new do
			loop do
				$>.flush
				sleep 3
			end
		end
		puts
		puts '=== ' + Time.now.to_s + ' ' + '='*45  # date marker

		# run with 'below normal' CPU piority
		require 'win32/process'
		Process.setpriority(Process::PRIO_PROCESS, 0, Process::BELOW_NORMAL_PRIORITY_CLASS)
	end

	def sync
		@sync ||= Sync.new(
			local: @local || @local_1,
			# *for .down we ensure that set_dir will be not the same as for .up
			set_mod: @local==@local_2 ? '(2)' : '',
			# multiple dirs sample
#			local:
#				dir_1: 'C:/path/to/dir_1'
#				dir_2: 'D:/path/to/dir_2'
			conf: {
				# default: 5 MB
				pack_max_size_bytes: 10.MB
			}
		)
	end
end


# warn & trace as puts
def w(t='warn')
	puts t.to_s
end

App.new.cmd

