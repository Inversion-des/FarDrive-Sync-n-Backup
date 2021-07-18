class Array

	# -wording
	alias :includes? include?
	alias :divide_by partition
	alias :n size

	# -median
	# returns integer or float
	def median
		return 0 if self.empty?
		len = self.length
		sorted = self.sort
		len % 2 == 1 ? sorted[len/2] : (sorted[len/2 - 1] + sorted[len/2]).to_f / 2
	end

	def avrg
		return nil if empty?
		sum.fdiv size
	end


	# -index
	# Creates hash with keys from values of array
	#  arr = ['k1', 'k2', 'k1']
	#  arr.create_index   #=> {"k1"=>1, "k2"=>1}
	def create_index
		Hash[ self.map {|k| [k, 1] } ]
	end


	# -- for arr of hashes

	#	data = [
	#		{_id:'k1', d:1 },
	#		{_id:'k3', d:3 },
	#		{_id:'k2', d:2 },
	#	]

	# -index arr of hashes/objects by some key
	# create index by some key
	# index = data.create_index_by :_id —> {"k1"=>{:_id=>"k1", :d=>1}, "k3"=>{:_id=>"k3", :d=>3}, "k2"=>{:_id=>"k2", :d=>2}}
	# by_way_id = ways.create_index_by 'data.way_id' — deep index (doesn't work for objects)
	# *sym_keys:true — convert keys to symbols
	# *no_vals:true — creates index with 1 instead of data
	def create_index_by(key, no_vals:false, sym_keys:false)
		f_hash = self.first&.respond_to?('[]')
		Hash[
			self.map do |d|
				# deep
				if key.is_a?(String) && key.includes?('.')
					# *Ruby 2.3 needed
					parts = key.split '.'
					k = d.dig *parts
					# try symbols if no result by strings
					k ||= d.dig *parts.map(&:to_sym)
				else
					k = f_hash ? d[key] : d.send(key)
				end
				k = k.to_sym if sym_keys
				v = no_vals ? 1 : d
				[k, v]
			end
		]
	end
	alias :index_by create_index_by

	# -find_by key in arr of hashes
	# data.find_by(_id:'k3') —> {_id:'k3', d:3 }
	# data.find_by(d:2) —> {_id:'k2', d:2 }
	# index for each key is created and cached on the first search
	def find_by(o)
		key = o.keys[0]
		val = o[key]
		@index_h ||= {}
		@index_h[key] ||= self.create_index_by key
		@index_h[key][val]
	end

	# -index arr of hashes/objects by block result as [key, val]
	# index_to = files[to].index_as  [~file.name, file]
	def index_as
		arr = self.map {|_| yield _ }
		return Hash[arr]
	end

	# -- /for arr of hashes


	def drop_last(n=1)
		self[0...-n]
	end

	def map_compact(&blk)
		map(&blk).compact
	end

	# for a1 = [1,2,3]; a2 = [1,2,2,4,4]
	# a2.changes_from(a1)
	# {2=>+1, 3=>-1, 4=>+2}
	def changes_from(a1)
		a2 = self
		{}.tap do |res|
			for k in (a1 | a2).sort
				diff = a2.count(k) - a1.count(k)
				res[k] = diff if diff != 0
			end
		end
	end


	# *used in places where long text exceeds limist (like in push notifications)
	# data.deep_truncate! 100
	def deep_truncate!(*o)
		for v in self
			case v
				when String
					v.truncate! *o
				when Hash, Array
					v.deep_truncate! *o
			end
		end
	end

end
