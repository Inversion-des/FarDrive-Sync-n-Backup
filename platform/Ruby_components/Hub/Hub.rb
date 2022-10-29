class Hub
	def initialize
		@subs_by_msg = Hash.new {|h, k| h[k]=[] }
	end
	def fire(msg, *data)
		# pass the last hash param as keywords
		# allows to use like:  @hub.on :ask_confirmation do |e, o, on_yes:, on_no:nil|
		#		where o is a hash with arbitrary data
		o = {}
		if data.last.is_a?(Hash)
			o = data.pop
		end

		for blk in @subs_by_msg[msg]
			blk.call msg, *data, **o
		end
	end
	def on(*msgs, &blk)
		for msg in msgs
			@subs_by_msg[msg] << blk
		end
	end
end
