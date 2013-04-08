require 'socket'
require 'enum'
require 'timeout'
require 'benchmark'
require 'securerandom'

module NSCA
	class Client
		class Connection
			attr_reader :iv_key, :timestamp, :socket, :packet_version, :password

			def self.open *args
				conn = new *args
				if block_given?
					begin yield conn
					ensure conn && conn.close
					end
				else conn
				end
			end

			# opts must be a hash
			# Connection.new host, port [, opts]
			# Connection.new socket [, opts]
			# Connection.new host, opts # need `opts = {port: Port}`!
			# Connection.new opts # need `opts = {port: Port, hostname: Hostname}`!
			# Connection.new opts # need `opts = {port: Port, socket: Socket}`!
			def initialize *args
				opts = {}
				opts = args.pop.dup  if args.last.is_a? Hash
				opts[:host] ||= opts[:hostname]
				opts[:sock] ||= opts[:socket]
				opts[:pass] ||= opts[:password]

				case args[0]
				when String
					opts[:host] = args[0]
					opts[:port] ||= args[1]
				when IO
					opts[:sock] = args[0]
				end

				@socket = if opts[:sock].is_a? IO
						opts[:sock]
					elsif opts[:host].is_a? String
						TCPSocket.new opts[:host], opts[:port]
					else
						raise ArgumentError, "Socket or hostname+port expected."
					end
				@packet_version = opts[:packet_version] || PacketV3

				# read iv_key and timestamp
				iv_key_and_timestamp = @socket.recv 132
				@iv_key, ts = iv_key_and_timestamp.unpack 'a128N'
				@timestamp = Time.at ts
				@password = opts[:pass]
			end

			# Builds a check-result-line for NSCA.
			#
			# Will be terminated by end-of-terminate.
			# @param [Time,Integer,nil] timestamp Checked at this time
			# @param [0..3] return_code `NSCA::ReturnCode`
			# @param [String(length<64),nil] hostname If nil, local hostname will be used.
			#                                         Must be known by Nagios.
			# @param [String(length<128)] service Name of Service. Must be known by Nagios.
			# @param [String(length<512)] status Status-line inclusive optional Performance Data.
			def build_packet timestamp, return_code, hostname, service, status
				packet = @packet_version.new timestamp || @timestamp, return_code, hostname, service, status
				packet.build @iv_key
			end

			# Sends a check-result.
			# @see #build_packet
			def send_packet( *a)  @socket.write build_packet( *a)  end

			# Sends check-results
			# @param [Array<NSCA::Check::Base>] results
			def send *results
				results.flatten.each do |r|
					send r.timestamp, r.retcode, r.hostname, r.service, r.text
				end
			end

			# Closes connection to NSCA.
			def close( *a)  @socket.close( *a)  end
		end

		attr_reader :socket_or_host, :port, :password
		def initialize socket_or_host = nil, port = nil, password = nil, &connect
			@socket_or_host, @port, @password = socket_or_host, port, password
		end

		def open &e
			Connection.open @socket_or_host, @port, @password, &e
		end

		def send( *results) open {|conn| conn.send results } end
	end
end
