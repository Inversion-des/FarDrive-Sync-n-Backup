require_relative 'and'
# -not
# [1,2,3].not.empty? — true
# [1,2,3].isnt.empty? — true
# [].not.empty? — false
# [1,2,3].not.include? 4 — true
# nil.not.empty? — false, so .and.not is redundant

# if the first obj is nill
# group.and.not.member?(_uid:1) — nil
# group.not.member?(_uid:1) — nil
# @file_handle.and.not.closed? — nil
# @file_handle.not.closed? — nil
module Not
	module ObjExtension
		def not
			InverseReturner.new(self)
		end
		alias :isnt not
	end
	
	class InverseReturner
		def initialize(obj)
			@obj = obj
		end

		# *in? extend Object so we have to redefine it here
		def in?(*args)
			!@obj.in?(*args)
		end
		def method_missing(*args)
			return false if (@obj == nil && args[0] == :empty?)
			return nil if @obj == nil || @obj.is_a?(And::NilReturner)
			!@obj.send(*args)
		end
	end
end

class Object
	include Not::ObjExtension
end
