class Hash

	# -deep clone (-clone -dup -copy)
	def deep_dup
		Marshal.load(Marshal.dump self)
	end
	alias :deep_clone deep_dup
		
	def |(oth)
		self.empty? ? oth : self
	end

	# -deep merge (-merge)
	def deep_merge(second)
		return self if !second
		merger = proc do |key, v1, v2|
			Hash === v1 && Hash === v2 ?
				v1.merge(v2, &merger) :
				Array === v1 && Array === v2 ?
					v1 | v2 :
					[:undefined, nil, :nil].include?(v2) ?
						v1 : v2
		end
		self.merge(second, &merger)
	end

	def deep_merge!(second)
		self.replace self.deep_merge(second)
	end

	# -deep ensure (-ensure)
	def deep_ensure(second)
		merger = proc do |key, v1, v2|
			Hash === v1 && Hash === v2 ?
				v1.merge(v2, &merger) :
				Array === v1 && Array === v2 ?
					v1 :
					[:undefined, nil, :nil].include?(v1) ?
						v2 : v1
		end
		self.merge(second, &merger)
	end

	def deep_ensure!(second)
		self.replace self.deep_ensure(second)
	end


	# -except -without -wo
	# active_support/core_ext/hash/except
	# Returns a hash that includes everything but the given keys.
	#	 hash = { a: true, b: false, c: nil }
	#	 hash.except(:c) # => { a: true, b: false }
	#	 hash.except([:c]) # => { a: true, b: false }
	#	 hash # => { a: true, b: false, c: nil }
	def except(*keys)
		self.dup.except! *keys
	end
	alias :without except
	alias :wo except

	# Replaces the hash without the given keys.
	#	 hash = { a: true, b: false, c: nil }
	#	 hash.except!(:c) # => { a: true, b: false }
	#	 hash # => { a: true, b: false }
	def except!(*keys)
		keys.flatten.each {|_| self.delete _ }
		self
	end

	# -only
	# doesn't modify original
	#	 hash = { a: true, b: false, c: nil }
	#	 hash.only(:b, :a) # => { a: true, b: false }
	#	 hash.only([:b, :a]) # => { a: true, b: false }
	#	 hash # => { a: true, b: false, c: nil }
	def only(*keys)
		keys.flatten!
		self.select {|k, v| keys.includes? k }
	end

	# Keep only some keys
	#	 hash = { a: true, b: false, c: nil }
	#	 hash.only!(:b) # => { b: false }
	#	 hash # => { b: false }
	def only!(*keys)
		keys.flatten!
		self.select! {|k, v| keys.includes? k }
		self
	end


	# h.delete_keys! :k1, :k2
	# h.delete_keys! [:k1, :k2]
	# h.delete_key! :k3
	def delete_keys!(*arr)
		arr.flatten! if arr[0].is_an? Array
		for k in arr
			self.delete k.to_s
			self.delete k.to_sym
		end
	end
	alias :delete_key! delete_keys!

	# *used in places where long text exceeds limist (like in push notifications)
	# data.deep_truncate! 100
	def deep_truncate!(*o)
		for k, v in self
			case v
				when String
					v.truncate! *o
				when Hash, Array
					v.deep_truncate! *o
			end
		end
	end
end


