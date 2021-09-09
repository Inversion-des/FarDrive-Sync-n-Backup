
def pputs t
	puts
	puts t
end
def putss t
	puts t
	puts
end

# true.is_a?(Bool) #=> true
# false.is_a?(Boolean) #=> true
# case var
#		when Numeric, Bool then …
# alternative: [true, false].include? var
module Boolean; end
Bool = Boolean   # alias
class TrueClass; include Boolean; end
class FalseClass; include Boolean; end

class Mutex
	alias :sync synchronize
	def sync_if_needed
		if owned?
			yield
		else
			synchronize do
				yield
			end
		end
	end
end