# FarDrive Sync&Backup
# Copyright © 2021 Yura Babak (yura.des@gmail.com, https://www.facebook.com/yura.babak, https://www.linkedin.com/in/yuriybabak)
# License: GNU GPL v3.0 (https://www.gnu.org/licenses/gpl-3.0.html)

class ZipEngine
	def initialize(fp:nil, zip:nil)
		@zip = zip
		_ = fp
		@file = IFile.new _ if _
	end
	def save_as(fp)
		@file = IFile.new fp
		close
	end
	def close
		:stub
	end
end


# not finished
class The7Zip < ZipEngine
	BIN = 'D:/Designing/#Base/7z/7za'
	def add(fp)
		# -mx[N] : set compression level: -mx1 (fastest) ... -mx9 (ultra)
		`#{BIN} a -mx5 "#{@file.name}" "#{fp}"`
		@last_fp = fp
	end
	def rem_last
		rem @last_fp
	end
	def rem(fp)
		`#{BIN} d "#{@file.name}" "#{fp}"`
	end
	def size
		@file.size
	end
end


# not finished
class RubyZip < ZipEngine
	def initialize(**up)
		# one-time setup
		if require 'zip'
			# Zip.default_compression = Zlib::NO_COMPRESSION
			# Zip.default_compression = Zlib::DEFAULT_COMPRESSION
			Zip.default_compression = Zlib::BEST_COMPRESSION
		end
		super
		@buffer = StringIO.new
		@zip = Zip::File.new '', create=true, buffer=true
	end
	def add(fp)
		@zip.add File.basename(fp), fp
		commit
		@last_fp = fp
	end
	def rem_last
		rem @last_fp
	end
	def rem(fp)
		@zip.remove File.basename(fp)
		commit
	end
	def commit
		#. *needed to correctly rewrite to smaller content (after .rem)
		@buffer.truncate 0
		@zip.write_buffer @buffer
	end
	def close
		@file.binwrite @buffer.string
	end
	def size
		@buffer.size
	end
	def files_n
		@zip.size
	end
end


class Ruby7Zip < ZipEngine
	@@compressed_size_by_fp = {}
	attr :files
	def initialize(**up)
		# *patch once
		if require 'seven_zip_ruby'
			# *patch to remove mutex (so zips in 2 threads will really work in parallel and no issues)
			#	 real results: down from LocalFS became 2x faster (CPU usage increased from 30% to 75%)
			#   tests: total time not improved
			for cls in [SevenZipRuby::Writer, SevenZipRuby::Reader]
				cls.send :remove_const, :COMPRESS_GUARD   # avoid: warning: already initialized constant
				cls.const_set :COMPRESS_GUARD, nil
			end
		end
		super
		@size = 0
		@files = []
		@cache_data_by_fp = {}
	end
	def config(zip)
		# Compression level: 0, 1, 3, (5), 7 or 9
		# 21.09.22: changed 5 -> 7 (for many PSD files takes too long)
		zip.level = 5
		# Compression method: “LZMA”, (“LZMA2”), “PPMd”, “BZIP2”, “DEFLATE” or “COPY”
		zip.method = 'LZMA2'
		# zip.solid = false
		# zip.multi_thread = no   # by default it uses multiple cores
	end
	def base_size
		@base_size ||= begin
			tmp_buffer = StringIO.new
			SevenZipRuby::Writer.open tmp_buffer do |zip|
				config zip
				zip.add_data '_', '_.dat'
			end
			tmp_buffer.size
		end
	end

	# < added file compressed size
	def add(file, as:nil)
		file.d.as = as || file.name
		fp = file.path
		@files << file
		# check file compressed size (in memory)
		size = @@compressed_size_by_fp[fp] ||= begin
			tmp_buffer = StringIO.new
			SevenZipRuby::Writer.open tmp_buffer do |zip|
				config zip
				# *this way ignores files attributes
				data = @cache_data_by_fp[fp] = file.binread
				zip.add_data data, file.d.as
				# zip.add_file fp, as:File.basename(fp)
			end
			#. cache zip result for reuse if this file will be zipped alone
			file.d.zip_data = tmp_buffer.string
			@@compressed_size_by_fp[fp] = tmp_buffer.size - base_size
		end
		@size += size
		size
	end
	def rem_last
		rem @files.last
	end
	def rem(file)
		@files.delete file
		clear_file_d file
		@size -= @@compressed_size_by_fp[file.path]
	end
	def clear_file_d(file)
		file.d.delete_keys! :zip_data, :as
	end
	def close
		data = 
			# *if only 1 file to compress — resuse cached compression result
			if @files.n == 1 && (d=@files[0].d.zip_data)
				clear_file_d @files[0]
				d
			else
				buffer = StringIO.new
				SevenZipRuby::Writer.open buffer do |zip|
					config zip
					for file in @files
						# *this way ignores files attributes
						data = @cache_data_by_fp[file.path] || file.binread
						# (LONG? - no only when the block is finished — it is compressed)
						zip.add_data data, file.d.as
						# zip.add_file fp, as:File.basename(fp)
						clear_file_d file
					end
					# -- (LONG) all files added — now .compress is called --
				end
				buffer.string
			end
		@file.binwrite data
		@cache_data_by_fp.clear
	end
	# -size -factor -k
	def size
		# *solid archive result size for multiple files is usually smaller, so here we try to estimate real final size
		#  - tried to add dependance from files count but it caused sometimes that total size decreased after adding some small file and the pack calibration logic was broken
		@files.n == 1 ? @size : @size.div(1.1)
	end
	# cls.new(fp:'db2.7z').pack_dir dir_or_path, skip_by_path:['path']|{'path' => 1}
	def pack_dir(path, skip_by_path:{})
		if skip_by_path.array?
			skip_by_path = skip_by_path.create_index
		end
		dir = IDir.new path
		# *this operation can fail with an error: UpdateItems error (StandardError)
		#  if some added file is deleted in the middle of the compression process (deletion of DirDB tmp file caused this)
		SevenZipRuby::Writer.open_file(@file) do |zip|
			for file in dir.files
				# *skip DirDB tmp files
				next if skip_by_path[file.path] || file.name.includes?('__tmp.')
				zip.add_file file, as:file.name
			end
			dir.dirs.each do |subdir|
				next if skip_by_path[subdir.path]
				dir.in do
					zip.add_directory subdir.path
				end
			end
		end
	end
	# zip = StringIO.new IFile.new('R:\remote\.db.7z').binread
	# cls.new(:zip:).unpack_all to:dir
	def unpack_all(to:nil)
		SevenZipRuby::Reader.extract_all @zip, to
	end
	# cls.new(:zip:).unpack_files(arr) do |d, file_body|
	def unpack_files(fnames)
		SevenZipRuby::Reader.open(@zip) do |zip|
			entry_by_fname = Hash[
				zip.entries.map {|_| [_.path, _] }
			]
			# *tried to extract entry one-by-one and it was extremly slow: file_body = zip.extract_data entry
			list = fnames
				.map do |name|
					# *sometimes there are errors (no such file in the pack)
					entry_by_fname[name].tap do |_|
						w "(unpack_files) error: '#{name}' file missed in the pack" if !_
					end
				end
				.reject(&:nil?)
				.sort_by(&:index)  	# *if not sorted by index — some file_body is nil
			zip.extract_data(list).each_with_index do |file_body, i|
				fname = list[i].path
				yield fname, file_body
			end
		end
	end
end

