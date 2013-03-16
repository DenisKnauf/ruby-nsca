require 'socket'
require 'enum'
require 'timeout'
require 'benchmark'

module NSCA
	class ReturnCode <Enum
		start_at 0
		enum %w[OK WARNING CRITICAL UNKNOWN]
	end

	# This class losly based on send_nsca `SendNsca::NscaConnection`-class.
	class Connection
		PACKET_VERSION = 3 # NSCA 2.9
		# packet-version crc32 timestamp return-code hostname service status(incl perfdata) EOT
		PACK_STRING = "n     N         N           n      a64    a128                 a4096   C"
		EOT = 0x17 # Seperator for more than one entry

		attr_reader :xor_key, :timestamp, :socket

		def initialize socket_or_host, port = nil
			@socket = case socket_or_host
				when String then Net::TCPSocket.new socket_or_host, port
				else socket_or_host
				end
			# read xor_key and timestamp
			xor_key_and_timestamp = @socket.recv 132
			@xor_key, ts = xor_key_and_timestamp.unpack 'a128L'
			@xor_key_a = @xor_key.unpack 'C*' # needed for every xor
			@timestamp = Time.at ts
		end

		def xor msg
			key_a = @xor_key_a
			# Slice the message in parts of length key_a.length.
			# XOR each char of a part with char at the same index in key_a.
			msg.unpack( 'C*').each_slice( key_a.length).inject do |res, part|
				res += part.zip( key_a).map {|a,b| a^b }.pack 'C*'
			end
		end

		def crc32 msg
			(msg.each_byte.inject 0xFFFFFFFF do |r,b|
				8.times.inject( r^b) {|r,_i| (r>>1) ^ (0xEDB88320 * (r&1)) }
			end) ^ 0xFFFFFFFF
		end

		# Builds a check-result-line for NSCA.
		#
		# Will be terminated by end-of-terminate.
		# @param [Time,Integer,nil] timestamp Checked at this time
		# @param [0..3] return_code `NSCA::ReturnCode`
		# @param [String(length<64),nil] hostname If nil, local hostname will be used.
		#                                         Must be known by Nagios.
		# @param [String(length<128)] service Name of Service. Must be known by Nagios.
		# @param [String(length<4096)] status Status-line inclusive optional Performance Data.
		def build_package timestamp, return_code, hostname, service, status
			entry = [
				PACKET_VERSION, # packet-version
				0, # crc32 (unknown yet)
				(timestamp || @timestamp).to_i,
				return_code.to_i,
				hostname || `hostname -f`,
				service,
				status # incl perfdata
			]
			# generate crc32 and put it at entry[2...6]
			xor "#{entry[0...2]}#{crc32 entry.pack( PACK_STRING)}#{entry[6..-1]}#{EOT.chr}"
		end

		# Sends a check-result.
		# @see #build_package
		def send( *a)  @socket.write build_package( *a)  end

		# Sends check-results
		# @param [Array<NSCA::Check::Base>] results
		def send_results *results
			results.flatten.each do |r|
				send r.timestamp, r.retcode, r.hostname, r.service, r.text
			end
		end

		# Closes connection to NSCA.
		def close( *a)  @socket.close( *a)  end
	end

	class Server
		attr_reader :socket_or_host, :port, :connect
		def initialize socket_or_host = nil, port = nil, &connect
			@socket_or_host, @port = socket_or_host, port
			@connect = connect || lambda { Connection.new @socket_or_host, @port }
		end

		def open &e
			conn = @connect.call
			if block_given?
				begin yield conn
				ensure conn && conn.close
				end
			else
				conn
			end
		end

		def send *results
			open do |conn|
				conn.send_results results
			end
		end
	end

	module PerformanceData
		class Base
			extend Timeout
			extend Benchmark

			def initialize value
				@value = value
			end

			class <<self
				attr_reader :label, :unit, :warn, :crit, :min, :max
				def init label, unit = nil, warn = nil, crit = nil, min = nil, max = nil
					@label, @unit, @warn, @crit, @min, @max = label.to_s, unit, warn, crit, min, max
					self
				end

				def measure &block
					timeout ||= 0
					exception = Class.new Timeout::Error
					pd = perfdatas[perfdata_label]
					timeout = pd.max
					m = realtime do
						begin
							timeout timeout, exception, &block
						rescue exception
						end
					end
					new m
				end
			end

			attr_reader :value
			def label()  self.label  end
			def unit()  self.unit  end
			def warn()  self.warn  end
			def crit()  self.crit  end
			def min()  self.min  end
			def max()  self.max  end

			def return_code
				if @value.nil? then 3
				elsif crit <= @value then 2
				elsif warn <= @value then 1
				else 0
				end
			end

			def to_s
				"#{label}=#{value}#{unit},#{warn},#{crit},#{min},#{max}"
			end
		end

		class <<self
			def create label, unit = nil, warn = nil, crit = nil, min = nil, max = nil
				cl = Class.new Base
				cl.init label, unit, warn, crit, min, max
			end

			def new label, unit = nil, warn = nil, crit = nil, min = nil, max = nil
				cl = create label, unit, warn, crit, min, max
				clname = NSCA::Helper.class_name_gen label
				self.const_set clname, cl  if clname
				cl
			end
		end
	end

	module Check
		class Base
			attr_reader :perfdatas, :return_code, :status, :timestamp
			def initialize return_code = nil, status = nil, perfdatas = nil
				@perfdatas = {}
				init return_code, status, perfdatas, timestamp || Time.now
			end

			def init return_code = nil, status = nil, perfdatas = nil, timestamp = nil
				@return_code = return_code  if return_code
				@status = status  if status
				perfdatas.each &method( :[])  if perfdatas
				@timestamp = timestamp  if timestamp
				self
			end

			def [] perfdata_label
				pd = @perfdatas[perfdata_label]
				pd && pd.value
			end

			def []= perfdata_label, value
				cl = self.class.perfdatas[perfdata_label]
				cl ||= PerformanceData::Base.create perfdata_label
				@perfdatas[perfdata_label] = cl.new value
			end

			def text
				r = "#{status || ReturnCode.find(return_code)}"
				r += " | #{perfdatas.map( &:to_s).join ' '}"  unless perfdatas.empty?
				r
			end

			def measure perfdata_label, &block
				@perfdatas[perfdata_label].measure &block
			end

			def send servers = nil
				NSCA.send self, servers
			end

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
				rc = self.class.perfdatas.map do |label, pdc|
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

			class <<self
				attr_reader :service, :hostname, :perfdatas
				def init service, hostname = nil, perfdatas = nil
					@service, @hostname, @perfdatas = service, hostname || `hostname -f`, {}
					perfdatas.each {|pd| @perfdatas[pd.label] = pd }
					self
				end

				def ok status = nil, perfdatas = nil
					new.ok status, perfdatas
				end

				def warning status = nil, perfdatas = nil
					new.warning status, perfdatas
				end
				alias warn warning

				def critical status = nil, perfdatas = nil
					new.warning status, perfdatas
				end
				alias crit critical

				def unknown status = nil, perfdatas = nil
					new.unknown status, perfdatas
				end
			end
		end

		def create service, hostname = nil, perfdatas = nil
			cl = Class.new Base
			cl.init service, hostname, perfdatas
			cl
		end

		def new service, hostname = nil, perfdatas = nil
			cl = create service, hostname, perfdatas
			clname = NSCA::Helper.class_name_gen service
			self.const_set clname, cl  if clname
			cl
		end
	end
	
	module Helper
		class <<self
			def class_name_gen label
				clname = label.gsub( /\W+/, '_').sub /^[0-9_]+/, ''
				return nil  if clname.empty?
				clname[0] = clname[0].upcase
				clname.to_sym
			end
		end
	end

	class <<self
		def servers()  @servers ||= []  end

		def send results, servers = nil
			Array.wrap( servers || NSCA.servers).each {|server| server.send results }
			self
		end
	end
end
