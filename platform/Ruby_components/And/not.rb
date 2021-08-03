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

	# *we should inherit from BasicObject to ensure that any method call will go to method_missing
	#   fixed: hash? returned always false because it was called for InverseReturner instance and not for @obj
	class InverseReturner < BasicObject
		def initialize(obj)
			@obj = obj
		end

		def method_missing(*args)
#$>.puts '---------------'
#::Kernel.p @obj
			return false if (@obj.nil? && args[0] == :empty?)
			return nil if @obj.nil? || @obj.is_a?(::And::NilReturner)
#::Kernel.p args
#::Kernel.p @obj.send(*args)
			!@obj.send(*args)
		end

		def inspect
			"<Not::InverseReturner>"
		end
	end
end

class Object
	include Not::ObjExtension
end
