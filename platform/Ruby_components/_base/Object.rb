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

	# '' | 'not found' => 'not found'
	def |(oth)
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
