class NilClass

	# nil[] => nil
	# helps to use non existin path in 'if'
	def [](p)
		nil
	end
	
	def |(oth)
		oth
	end
	
end