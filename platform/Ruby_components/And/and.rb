# -and
# h[:el].and.downcase == 'val'
# a[2].is.empty?
module And
	module ObjExtension
		def and
			self.nil? ? NilReturner.new : self
		end
		alias :is and
	end
	
	class NilReturner
		def method_missing(name, *args)
			return true if name == :empty?
			nil
		end
		
		# *needed for case: 
		#   d = @in_doc.and.data.and.dup || 2
		# without this dup will return NilReturner instance so '||' will not work as expected
		def dup
			nil
		end

		# do not call .then block, just return nil
		# for normal nil .then will be called
		def then
			nil
		end
	end
end

class Object
	include And::ObjExtension
end
