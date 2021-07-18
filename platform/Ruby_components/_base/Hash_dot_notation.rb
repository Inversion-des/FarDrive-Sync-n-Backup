class Hash

	# -dot notation
	# v = h.param
	# h.param = 'val'
	# deep also works: h.param.param = val

	# pros:
	# 	- 6x faster then OpenStruct (because a new class and object are not constructed)
	# 	- chained keys work: h.data._action
	#	- not needed to convert to hash later
	# cons:
	# 	- 8x slower then Hash
	# 	- you cannot use some methods native to Hash: .key, .sort, etc
	# 	- if hash contains some string-key (not symbol) — symbol copy will be created

	# !!! if param name is :key — h.key will not work, use h[:key] or h['key'].
	#		same for: h.sort, h.min, h.max (from enumerable)
	# Same problem with any other existing Hash method
	def method_missing(method, val=nil)
		m = method.to_s
		if m[-1] == '='
			m.chop!
			self[m.to_sym] = val
			self[m] = val if self.key? m
		else
			self.key?(m) ? self[m] : self[m.to_sym]
		end
	end
end