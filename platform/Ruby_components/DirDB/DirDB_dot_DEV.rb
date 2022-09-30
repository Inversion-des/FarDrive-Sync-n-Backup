# !!! should be inherited from DirDB.rb
# @db ?= DirDB.new(dir:$app_dir)
# @db = DirDB.new '.db_folder' — default .db
# @db.load — will load all files
# @db = DirDB.new('db_global').load 'storage_GoogleDrive' — load only one file
# @last_themes = @db.last_themes.names ||= []
# @db.node_data_by_path.default_proc ?= proc {|h, k| h[k]={} } — we have to use this, because ?= {{}} is ignored for existing hash
# @db.test[:now] = Time.now.to_i
# @db.last_themes_A — this will be an array
# @db.test.save — save this collection
# @db.save — save all collections
# add .save for some prop (additional to collection)
#   @db = sync_db.storages[key] ?= {}
#   sync_db.add_save!(@db, 'storages')
#   @db.save
# frozen_string_literal: true
#
# transaction of db: save only all listed cols together or none
# db.transaction_start [:data1, :data2], tx_mutex do
#		[prepare changes]
# end
#
# tx = db.transaction_start [:data1, :data2]
# db.data1.save
#  - process that can be interrupted -
# db.data2.save
# tx.finish — at this moment saved colname_.dat files will replace original .dat files
# test can be found by '# -transaction test' in _tests.rb

require '_base/Core'
require '_base/Array'
require '_base/FS'

class DirDB

	C_default_dir = '.db'

	# by default — dev
	# DirDB.prod! used for production (faster)
	# dev mode needed to be able to compare result db files in tests
	def DirDB.prod!
		@f_prod = true
	end
	def DirDB.dev?
		!DirDB.prod?
	end
	def DirDB.prod?
		@f_prod
	end

	# *bin — in prod use Marshal dump/load for these files (name, no ext)
	def initialize(dname=nil, dir:Dir.pwd, load:true, bin:[])
		@dname = dname&.to_s || C_default_dir
		@dir = IDir.new dir
		@bin = bin.create_index
		@ext = '.dat'
		@data_by_name = {}
		@mutex_by_name = {}
		@active_transactions = []
		@tx_by_name = {}
		self.load if load
	end

	# for k, v in @up_db
	#    @db.send "#{k}=", v
	def each(&blk)
		@data_by_name.each &blk
	end

	def map(&blk)
		@data_by_name.map &blk
	end
	def filter_map(&blk)
		@data_by_name.filter_map &blk
	end

	def dir
		@dir/@dname
	end

	def add_save!(obj, name)
		obj.instance_variable_set :@rel, self
		obj.instance_variable_set :@name, name
		def obj.save
			@rel.save only:@name
		end
	end

	def method_missing(name, data=nil)
		name = name.to_s
		if name.end_with? '='
			name.chop!
			obj = @data_by_name[name] = case
				when name.end_with?('_A') then data || []
				else data || {}
			end
			add_save!(obj, name)
		else
			@data_by_name[name] ||= begin
				obj = case
					when name.end_with?('_A') then []
					else {}
				end
				add_save!(obj, name)
				obj
			end
		end
	end
	# allow to get data by @db[name_var]
	def [](name)
		send name
	end

	def load(only_name=nil)
		# ensure dir exists
		@dir.create.in do
			# for each .dat file in the @dname (ignore subdirs)
			Dir.glob((only_name||'*')+@ext, base:@dname) do |fname|
				if name=File.basename(fname, @ext)
					path = @dname+'/'+fname
					if @bin[name] && DirDB.prod?
						begin
							# *if there is a saved inspect (old format) there will be error:
							#  incompatible marshal file format (can't be read)
							#  so we will fallback to eval
							data = Marshal.load(File.binread path)
						rescue TypeError
							puts "Marshal.load failed for #{name}, falling back to eval"
						end
					end
					if !data
						# *binread here causes of errors like:
						# `encode': "\\xC2" to UTF-8 in conversion from ASCII-8BIT to UTF-8 to UTF-16LE (Encoding::UndefinedConversionError)
						data = eval(File.read path)
					end
					self.send name+'=', data
				end
			end
		end
		if only_name
			self.send only_name
		else
			self
		end
	end

	# *helps to speedup tests cases where we emulate many iterations
	# app.db.buffer_saves
	# … many .save calls …
	# app.db.flush
	def buffer_saves
		@f_buffer_saves = true
		@buffer_only_H = {}
	end

	def flush
		@f_buffer_saves = false
		if @buffer_only_H.empty?
			save
		else
			for k, _ in @buffer_only_H
				save(only:k)
			end
		end
	end

	# *each col can be only in one tx at a time
	# *mutex needed to use same tx in parallel threads
	# << tx — to be able to do tx.finish
	def transaction_start(col_names, tx_mutex=nil)
		#. names to_s
		col_names.map! {|_| _.to_s }

		tx_mutex&.lock
		for name in col_names
			raise "(DirDB - transaction_start) '#{name}' collection is already in some active transaction" if @tx_by_name[name]
		end
		Transaction.new(self).tap do |tx|
			@active_transactions << tx
			for name in col_names
				@tx_by_name[name] = tx
			end
			tx.on_finish do
				@tx_by_name.delete_keys! col_names
				@active_transactions.pull tx
				tx_mutex&.unlock
			end
			if block_given?
				yield
				tx.finish
			end
		end
	end

	# << tx — to use tx.add_fn
	def in_transaction?(name)
		@tx_by_name[name]
	end


	def save(only:nil)
		# (<!)
		if @f_buffer_saves
			@buffer_only_H[only] = 1 if only
			return
		end

		begin
			# ensure @dname exists
			dir.create

			to_save = @data_by_name.dup
			to_save.select! {|k, v| k == only } if only

			for name, data in to_save
				check_data! name, data if DirDB.dev?
				mutex = @mutex_by_name[name] ||= Mutex.new
				mutex.synchronize do

					# save tmp file to do not corrupt original in case of an error
					tmp_file = dir/(name+'__tmp'+@ext)
					tmp_file.open 'wb' do |f|
						#			load				save				size
						# dev	0.366-0.385	2.085-2.116	1673K
						# prod	0.332-0.351	0.116-0.124	1576K
						#! ще можна спробувати різні джеми для JSON
						if DirDB.dev?
							# *saves with LF on Win
							require 'pp'
							PP.pp data, f, 150
						else
							if @bin[name]
								# {}.replace is a workaround for the error  singleton can't be dumped (TypeError)
								#  caused by changes for the hash in .add_save!
								Marshal.dump({}.replace(data), f)
							else
								# *saves with CRLF on Win
								f.write data.inspect
							end
						end
					end
					# replace the original if all is ok
					replace_ori = -> do
						tmp_file.move_to dir/(name+@ext)
					end

					if tx=(in_transaction? name)
						tx.add_fn name, replace_ori
					else
						replace_ori.()
					end

				end
			end
		end
	end

	# (>>>)
	# *used only if DirDB.dev?
	def check_data!(name, data)
		case data
			when String, Numeric, Bool, Regexp then :ok
			when Array then data.each {|el| check_data! name, el }
			when Hash then data.each {|k, v| check_data! k, v }
			else raise "(DirDB - save) error: bad data type for '#{name}': #{data.inspect} (#{data.class})"
		end
	end



	# -Transaction -tx
	class Transaction
		def initialize(db)
			@db = db
			@fn_by_name = {}
		end
		def add_fn(name, fn)
			# *will replace old fn if defined
			@fn_by_name[name] = fn
		end
		def on_finish(&block)
			@on_finish = block
		end
		def finish
			@fn_by_name.values.each &:call
			@on_finish&.()
		end
	end

end
