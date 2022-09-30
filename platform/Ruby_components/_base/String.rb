class String
	alias :includes? include?

	# '' | 'not found' => 'not found'
	def |(oth)
		self.strip.empty? ? oth : self
	end

	# -first -upper case -case -upcase
	def upcase_first
		return self if empty?
		dup.tap {|_| _[0] = _[0].upcase }
	end
	def upcase_first!
		replace upcase_first
	end

	def to_time
		Time.at self
	end

	def clear_tags
		self.gsub(/<[\/\w][^>]*>/, '')
	end

	def clear_tags!
		self.replace self.clear_tags
	end

	# -checksum
	def checksum
		# -checksum format (1/2)
		# 7 bytes
		Digest::SHA1.base64digest(self)[0, 7]
	end

	# based on https://apidock.com/rails/String/truncate
	# str.truncate 50
	# str.truncate 50, omission:'(cut)'
	# str.truncate 50, omission:'(cut)', separator:' '
	def truncate(max_len, o={})
		return self unless length > max_len

		o.omission ||= '...'
		max_len -= o.omission.length
		stop = o.separator \
			? (rindex(o.separator, max_len) || max_len)
			: max_len

		"#{self[0, stop]}#{o.omission}"
	end

	def truncate!(*o)
		self.replace self.truncate(*o)
	end
end
