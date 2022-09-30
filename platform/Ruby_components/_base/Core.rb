
PROD = ENV['PROD']
DEV = !PROD
TESTS = ENV['TESTS']


# add \n before or after the puts
def nputs(t)
	puts
	puts t
end
alias :pputs nputs
def putsn(t)
	puts t
	puts
end
alias :putss putsn


# true.is_a?(Bool) #=> true
# false.is_a?(Boolean) #=> true
# case var
#		when Numeric, Bool then …
# alternative: [true, false].include? var
module Boolean; end
Bool = Boolean   # alias
class TrueClass; include Boolean; end
class FalseClass; include Boolean; end

class FalseClass
	def |(oth)
		oth
	end
end


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


# *auto call mon_initialize (no need to remember to do super in init)
module MonitorMixin
	def sync(&b)
		mon_initialize if !@mon_data
		@mon_data.synchronize &b
	end
end