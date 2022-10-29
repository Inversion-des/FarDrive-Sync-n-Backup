# *frozen_string_literal: true — should not be used here to ensure unique object_id for ''

class ParaLines

	def initialize
		set_flags!
		@line_by_key = Hash.new {|h, key| h[key] = {line:h.length, col:1, text:''} }

		# *ensure flush at exit
		if @f_to_file
			at_exit do
				flush final:true
			end
			# flush every 3 sec in bg thread
			# *fixed problem that if there is an endless loop — there will be no output to file in the process and when you terminate the app
			Thread.new do
				loop do
					sleep 3
					flush
				end
			end
		end

		if block_given?
			begin
				yield self
			ensure
				flush final:true
			end
		end
	end

	# plines << "done (#{n})"
	def << (text)
		key = Thread.current
		output key, text
	end

	# plines.add_static_line '- 5 workers added'
	def add_static_line(text)
		key = text.object_id
		MUTEX.synchronize do
			d = @line_by_key[key]
			if @f_to_console
				puts text
			else  # for file
				d[:text] += text.to_s
			end
		end
	end

	# plines.add_empty_line
	def add_empty_line
		add_static_line ''
	end

	# done_order_line = plines.add_shared_line 'Done order: '
	# done_order_line << 'some text'
	# part = shared_line.part_open "#{n}… " + later: part.close '+'
	# *can output partial progress by adding dots: [LS   ] [cloud2…   ] --> [LS....] [cloud2…   ] — call .close('.' * done_count) multiple times with increasing number of dots
	# *this line can be used by many threads
	# << helper obj (shared line) with the <<, .part_open and .start_progress_bar methods
	def add_shared_line(text='')
		key = text.object_id
		output key, text
		# << helper obj (shared line)
		Object.new.tap do |shared_line|
			rel_plines = self
			line_by_key = @line_by_key
			f_to_console = @f_to_console

			shared_line.define_singleton_method :<< do |text|
				rel_plines.send :output, key, text
			end

			shared_line.define_singleton_method :part_open do |text_='…'|
				part_col = nil
				d = nil

				MUTEX.synchronize do
					d = line_by_key[key]   # should be inside mutex
					# *we replace placeholder chars like: … or _ or just the last char (order here needed for priority to be able to have _ in text and use … as a placeholder)
					part_col = d[:col] + (text_.index('…'.freeze) || text_.index('_'.freeze) || text_.length-1)

					rel_plines.send :output, key, text_
				end

				# << helper obj (part) with the .update/.close method
				Object.new.tap do |part|
					part.define_singleton_method :close do |end_text|
						# *print the closing chars in the saved position
						MUTEX.synchronize do
							if f_to_console
								rel_plines.send :print_in_line,
									lines_up: line_by_key.count - d[:line],
									col: part_col,
									text: end_text
							else  # for file
								d[:text][part_col-1, end_text.length] = end_text
							end
						end
					end
					class << part
						alias :update close
					end
				end
			end
			shared_line.define_singleton_method :start_progress_bar do |title, **o|
				ProgressBar.new title, **o.update(shared_line:shared_line)
			end
		end
	end

	# << helper obj (ParaLines) with the .update(done:5)/.update(done_index:4) methods
	def start_progress_bar(p, **o)
		ProgressBar.new p, **o.update(plines:self)
	end

	def ask(text)
		text += ': '
		key = text.object_id
		d = nil
		MUTEX.synchronize do
			d = @line_by_key[key]
			if @f_to_console
				print text
			else  # for file
				d[:text] += text.to_s
			end
		end
		answer = ((( $stdin.gets ))).chomp
		d[:text] += answer
		yield answer if block_given?
	end

	# plines.flush final:true
	# *needed only when @f_to_file
	# *can be called manually if the block form was not used and all the threads are finished
	def flush(final:false)
		MUTEX.synchronize do
			if @f_to_file
				# *rewind needed for periodical bg flush
				@initial_pos ||= STDOUT.pos
				STDOUT.pos = @initial_pos
				puts @line_by_key.map {|key, d| d[:text] }
			end
			@line_by_key.clear if final
		end
	end


	# *needed for rewriting in tests
	private \
	def set_flags!
		# *better to use STDOUT const instead of $>, because in tests we can redefine STDOUT for this class only
		@f_to_console = STDOUT.tty?
		@f_to_file = !STDOUT.tty?
#		@f_to_console = $>.tty?
#		@f_to_file = !$>.tty?
	end


	private \
	def output(key, text)
		text = text.to_s
		MUTEX.sync_if_needed do

			# add line
			puts if @f_to_console && !@line_by_key.has_key?(key)

			d = @line_by_key[key]

			if @f_to_console
				print_in_line(
					lines_up: @line_by_key.count - d[:line],
					col: d[:col],
					text: text
				)
			else  # for file
				# *we have to do this and not just  d[:text] += text  because part.update can add more text to the part then reserved
				#   and it should not move the start_pos for the next << operation. In the Ticker we check more_chars_used
				#   to resoleve overwriting for console and without these changes it added redundant gap for the file
				start_pos = d[:col]-1
				d[:text][start_pos..-1] = text
			end

			d[:col] += text.length
		end
	end


	private \
	def print_in_line(lines_up:, col:, text:)
		# \e[s — save cursor position
		# \e[nA — move n lines up
		# \e[nG — move to n-th column
		# \e[u — restore cursor position
		print <<~OUT.delete("\n")
			\e[s
			\e[#{lines_up}A
			\e[#{col}G
			#{text}
			\e[u
		OUT
	end


	# *this allows to change STDOUT like this:
	#   ParaLines::STDOUT = C_w_file
	private \
	def puts(t=nil)
		STDOUT.puts t
	end
	private \
	def print(t=nil)
		STDOUT.print t
	end


	MUTEX = Mutex.new
	def MUTEX.sync_if_needed
		if owned?
			yield
		else
			synchronize do
				yield
			end
		end
	end

end



class ParaLines::WaitPoint
	def initialize(name='?')
		@name = name
		@q = Queue.new
	end
	def wait
		# using defaults: delay:3, int:1
		Ticker["WaitPoint #{@name} took"] do
			((( @q.pop )))
		end
	end
	def done!
		@q << true
	end
end



#! can be created via method of shared_line / plines (as ProgressBar)
class ParaLines::Ticker
	def self.[](...)
		self.new(...)
	end

	def initialize(title='working', delay:3, int:1, plines:C_plines, shared_line:nil, tpl_start:nil, tpl_end:nil)
		@start = moment
		gap = shared_line ? ' ' : ''   # gap needed only if the shared_line passed
		f_initial_print_done = false
		took_part = nil
		thr = Thread.new do
			sleep delay
			loop do
				if !f_initial_print_done
					f_initial_print_done = true
					shared_line ||= plines.add_shared_line
					took_part = shared_line.part_open (tpl_start||'%{gap}[%{title} ….0 s]') % {gap:gap, title:title}
				end
				took_part.update "%.1f s…" % seconds
				sleep int
			end
		end

		@on_stop = -> do
			thr.kill
			# close took_part
			if took_part
				# reserve more chars for took_part so the next << output to this line will not overwrite some last chars
				seconds_part = "%.1f" % seconds
				more_chars_used = seconds_part.length - 3
				if more_chars_used > 0
					shared_line << ' '*more_chars_used
				end

				took_part.close (tpl_end||'%{seconds_part} s]') % {seconds_part:seconds_part}
			end
		end

		if block_given?
			((( yield )))
			@on_stop.()
		end
	end

	def stop
		@on_stop.()
	end

	def seconds
		moment - @start
	end
	def moment
		Process.clock_gettime Process::CLOCK_MONOTONIC
	end
end


# -progress bar
# created via method
# progress = ProgressBar["Processing 15 nodes", total:10]
# progress = C_plines.start_progress_bar "Processing 15 nodes", total:10
# progress = sline.start_progress_bar " Zipping", bar_len:5, total:10
#		progress.update done:5 | progress.inc
class ParaLines::ProgressBar
	def self.[](...)
		self.new(...)
	end
	def initialize(title='', bar_len:20, total:, plines:C_plines, shared_line:nil)
		@bar_len, @total = bar_len, total
		shared_line ||= plines.add_shared_line
		# (<!) edge case
		if total == 0
			shared_line << title
			return
		end
		@part = shared_line.part_open "#{title}: […#{' '*(bar_len-1)}]"
		@ticker = ParaLines::Ticker.new '', delay:0, int:0.5, shared_line:shared_line, tpl_start:' - ….0 s', tpl_end:'%{seconds_part} s '
		@done = 0
	end
	# *done_index — starting from 0
	def update(done:nil, done_index:nil)
		done ||= done_index+1
		part_done = (done.to_f / @total).clamp 0, 1
		@part.update 'o' * (@bar_len * part_done)
		@ticker.stop if part_done.to_i == 1
	end
	def inc
		@done += 1
		update done:@done
	end
end