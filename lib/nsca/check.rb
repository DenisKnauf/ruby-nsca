module NSCA
	module PerformanceData
		class Base
			extend Timeout
			extend Benchmark

			class <<self
				attr_reader :label, :unit, :warn, :crit, :min, :max
				def init label, unit = nil, warn = nil, crit = nil, min = nil, max = nil
					@label, @unit, @warn, @crit, @min, @max = label.to_s, unit, warn, crit, min, max
					self
				end

				def measure &block
					timeout ||= 0
					exception = Class.new Timeout::Error
					pd = perfdatas[perfdata_label.to_sym]
					timeout = pd.max
					m = realtime do
						begin
							timeout timeout, exception, &block
						rescue exception
						end
					end
					new m
				end

				def to_sym() label.to_sym end
			end

			attr_reader :value
			def initialize( value) @value = value end
			def label()  self.class.label  end
			def unit()  self.class.unit  end
			def warn()  self.class.warn  end
			def crit()  self.class.crit  end
			def min()  self.class.min  end
			def max()  self.class.max  end
			def to_s() "#{label}=#{value}#{unit},#{warn},#{crit},#{min},#{max}" end
			def to_sym() self.class.label.to_sym end

			def return_code
				if @value.nil? then 3
				elsif crit <= @value then 2
				elsif warn <= @value then 1
				else 0
				end
			end
		end

		class <<self
			def new label, unit = nil, warn = nil, crit = nil, min = nil, max = nil
				cl = Class.new Base
				cl.init label, unit, warn, crit, min, max
			end

			def create label, unit = nil, warn = nil, crit = nil, min = nil, max = nil
				cl = new label, unit, warn, crit, min, max
				clname = NSCA::Helper.class_name_gen label
				self.const_set clname, cl  if clname
				cl
			end
		end
	end

	module Check
		class Base
			attr_accessor :return_code, :status, :timestamp
			attr_reader :perfdatas

			def initialize return_code = nil, status = nil, perfdatas = nil
				@perfdatas = {}
				init return_code, status, perfdatas, timestamp || Time.now
			end

			def init return_code = nil, status = nil, perfdatas = nil, timestamp = nil
				@return_code = return_code  if return_code
				@status = status  if status
				case perfdatas
				when Hash
					perfdatas.each &method( :[])
				when Array
					push *perfdatas
				end
				@timestamp = timestamp  if timestamp
				self
			end

			def [] perfdata_label
				pd = @perfdatas[perfdata_label.to_sym]
				pd && pd.value
			end

			def push *perfdatas
				perfdatas.each {|perfdata| @perfdatas[perfdata.label] = perfdata }
				@perfdatas
			end

			def perfdata_for label
				if label.is_a? PerformanceData::Base
					label
				else
					label = label.to_sym
					self.class.perfdatas[label] || PerformanceData::Base.new( label)
				end
			end

			def []= perfdata_label, value
				return push value  if value.is_a? PerformanceData::Base
				@perfdatas[perfdata_label] = perfdata_for( perfdata_label).new value
			end

			def text
				r = "#{status || ReturnCode.find(return_code)}"
				r += " | #{perfdatas.each_value.map( &:to_s).join ' '}"  unless perfdatas.empty?
				r
			end

			def measure perfdata_label, &block
				push perfdata_for( perfdata_label).measure( &block)
			end
			def send() NSCA::send self end

			def ok status = nil, perfdatas = nil
				init ReturnCode::OK, status, perfdatas
				send
			end

			def warning status = nil, perfdatas = nil
				init ReturnCode::WARNING, status, perfdatas
				send
			end
			alias warn warning

			def critical status = nil, perfdatas = nil
				init ReturnCode::CRITICAL, status, perfdatas
				send
			end
			alias crit critical

			def unknown status = nil, perfdatas = nil
				init ReturnCode::UNKNOWN, status, perfdatas
				send
			end

			def determine_return_code
				self.class.perfdatas.map do |label, pdc|
					pd = @perfdatas[label]
					if pd
						pd.return_code
					else
						-1
					end
				end.max
			end

			def retcode
				rc = return_code || determine_return_code
				(0..3).include?(rc) ? rc : 3
			end

			def service() self.class.service end
			def hostname() self.class.hostname end

			class <<self
				attr_reader :service, :hostname, :perfdatas
				def init service, hostname = nil, perfdatas = nil
					@service, @hostname, @perfdatas = service, hostname || `hostname -f`, {}
					perfdatas.each {|pd| @perfdatas[pd.label.to_sym] = pd }
					self
				end

				def ok( status = nil, perfdatas = nil) new.ok status, perfdatas end
				def warning( status = nil, perfdatas = nil) new.warning status, perfdatas end
				alias warn warning
				def critical( status = nil, perfdatas = nil) new.warning status, perfdatas end
				alias crit critical
				def unknown( status = nil, perfdatas = nil) new.unknown status, perfdatas end
			end
		end

		class <<self
			def new service, hostname = nil, perfdatas = nil
				cl = Class.new Base
				cl.init service, hostname, perfdatas
				cl
			end

			def create service, hostname = nil, perfdatas = nil
				cl = new service, hostname, perfdatas
				clname = NSCA::Helper.class_name_gen service.to_s
				self.const_set clname, cl  if clname
				cl
			end
		end
	end

	module Checks
		def perfdata( *params) NSCA::PerformanceData.new( *params) end

		def check service, hostname, perfdatas = nil
			perfdatas ||= []
			perfdatas.map! {|cl| cl.is_a?( Symbol) ? const_get( cl) : cl }
			NSCA::Check.new service, hostname, perfdatas
		end
	end
end
