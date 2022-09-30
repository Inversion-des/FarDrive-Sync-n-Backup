class Object

	# -wording
	alias :is_an? is_a?

	def numeric?
		is_a? Numeric
	end
	def string?
		is_a? String
	end
	def array?
		is_a? Array
	end
	def hash?
		is_a? Hash
	end
	def regexp?
		is_a? Regexp
	end

	def |(oth)
		self
	end


	# sort document recursively (doesn't touch arrays)   -sort -recursively -hash -json
	# obj.sort_recursively!
	# *based on — http://stufftohelpyouout.blogspot.com/2013/11/recursively-sort-arrays-and-hashes-by.html
	def sort_recursively
		case self
			when Array
				#* !arrays should not be sorted! — sorting breaks ordered data like rating
				# .sort_by!{|v| (v.to_s rescue nil) }
				self.map &:sort_recursively
			when Hash
				Hash[Hash[self.map{|k,v| [k.sort_recursively, v.sort_recursively]}].sort_by{|k,v| [(k.to_s rescue nil), (v.to_s rescue nil)]}]
			else
				self
		end
	end

	def sort_recursively!
		case self
			when Array, Hash
				self.replace sort_recursively
			else
				self
		end
	end


	# obj.deep_symbolize_keys!
	def deep_symbolize_keys
		case self
			when Hash
				self.inject({}){|memo, (k,v)| memo[k.to_sym] = v.deep_symbolize_keys; memo}
			when Array
				self.inject([]){|memo, v| memo << v.deep_symbolize_keys; memo}
			else self
		end
	end
	def deep_symbolize_keys!
		self.replace self.deep_symbolize_keys
	end

	# h.strip_strings! (-strip)
	# modified this solution
	# http://stackoverflow.com/a/24686236/364392
	def strip_strings!
		case self
			when Hash
				self.each do |k,v|
					case v
						when String then v.strip!
						else v.strip_strings!
					end
				end
			when Array
				for v in self
					case v
						when String then v.strip!
						else v.strip_strings!
					end
				end
			else
				self
		end
	end

	# -remove empty params (-empty, -clear)
	# *progressive:true — will repeat processing if new empty params created
	def remove_empty_params!(progressive:nil)
		case self
			when Hash
				self.each do |k,v|
					case v
						when Hash, Array
							if v.empty?
								self.delete(k)
							else
								v.remove_empty_params!(progressive:progressive)
								self.delete(k) if progressive && v.empty?
							end
						when NilClass, String then self.delete(k) if v.is.empty?
					end
				end
			when Array
				for v in self
					Hash v.remove_empty_params!(progressive:progressive) if v.is_a? Hash
				end
			else
				self
		end
		self
	end

	# -in? (-in )
	# 'Dog'.in? ['Cat', 'Dog', 'Bird']
	# 'Dog'.in?('Cat', 'Dog', 'Bird')
	# 'Dog'.in? %w[Cat Dog Bird]
	# 'Unicorn'.not.in?('Cat', 'Dog', 'Bird')
	# 1.in?(1, 2)
	# 1.in?(1..2)
	# 3.not.in?(1, 2)
	# works for: Array, Range (Enumerable)
	# based on: https://apidock.com/rails/Object/in%3F
	def in?(*args)
		collection = args[0].is_an?(Enumerable) ? args[0] : args
		collection.include? self
	rescue NoMethodError
		raise ArgumentError, 'The parameter passed to #in? must respond to #include?'
	end

end
