# for both Integer and Float  -Numeric
class Numeric

	# -limit min/max (-min -max -clamp)
	# (was_count-1).limit_min(0)
	def limit_min(min)
		[self, min].max
	end
	def limit_max(max)
		[self, max].min
	end

	# -size
	# storage size -> bytes
	# 5.MB, 1.GB
	def KB
		(self*1024).to_i
	end
	def MB
		(self*1024.KB).to_i
	end
	def GB
		(self*1024.MB).to_i
	end
end


class Integer
	# for -time
	def min
		self*60
	end
	alias :mins min
	alias :minute min
	alias :minutes min

	def hour
		self*60.mins
	end
	alias :hours hour

	def day
		self*24.hours
	end
	alias :days day

	def month
		self*30.days
	end
	alias :months month

	# -ago
	# 1.day.ago
	def ago(moment=Time.now)
		moment - self
	end

	def to_time
		Time.at self
	end

	# readable file size
	# file.size.readable
	# file.size.hr in_:'MB'
	def readable(in_:nil, html:nil)
		size = self.to_f
		res = case
			when size < 1.KB then "%d B" % size
			when size < 1.MB || in_=='KB' then "%.1f KB" % (size / 1.KB)
			when size < 1.GB || in_=='MB' then "%.1f MB" % (size / 1.MB)
			else "%.3f GB" % (size / 1.GB)
		end\
			.sub(/\.0+ /, ' ')  	# 1.0 MB => 1 MB
		res.sub!(/\.\d+/, '<i>\&</i>') if html == 'fraction'
		res
	end
	# human readable
	alias :hr readable

	# -say time  -time
	def say_time(o={})
		o[:show_zero_s] ||= false
		sec_passed = self
		days = sec_passed/86400
			sec_passed -= days*86400
		hours = sec_passed/3600
			sec_passed -= hours*3600
		minutes = sec_passed/60
		seconds = sec_passed - minutes*60

		arr = []
		arr << "#{days}d" if days>0
		arr << "#{hours}h" if hours>0
		arr << "#{minutes}m" if minutes>0
		# show seconds if < 3 mins
		arr << "#{seconds}s" if (minutes<3 && seconds > 0 || o[:show_zero_s])

		arr.join ' '
	end
end


class Float
	def say_time
		if self<60
			"%.1fs" % self
		else
			self.to_i.say_time
		end
	end
end
