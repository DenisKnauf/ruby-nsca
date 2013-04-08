require 'socket'
require 'enum'
require 'timeout'
require 'benchmark'
require 'securerandom'

module NSCA
	class Server
		attr_reader :iv_key, :server, :packet_version, :password
		def initialize *args
			opts = {}
			opts = args.pop.dup  if args.last.is_a? Hash
			opts[:host] ||= opts[:hostname]
			opts[:sock] ||= opts[:socket]
			opts[:pass] ||= opts[:password]

			case args[0]
			when Integer
				opts[:port] = args[0]
				opts[:host] ||= args[1]
			when IO
				opts[:sock] = args[0]
			end

			@packet_version = opts[:packet_version] || PacketV3
			@iv_key = (opts[:iv_key] || SecureRandom.random_bytes( 128)).to_s
			raise ArgumentError, "Key must be 128 bytes long"  unless 128 == @iv_key.length
			@password = opts[:pass].to_s
			@server = if opts[:serv].is_a?( TCPServer) or opts[:serv].is_a?( UNIXServer)
					opts[:serv]
				elsif opts[:port].is_a? Integer
					TCPServer.new *[opts[:port], opts[:host]].compact
				else
					raise ArgumentError, "Server or port-number expected"
				end
		end

		def accept() Connection.new @server.accept, self end
		def close() @server.close end

		class Connection
			def initialize socket, server
				@socket, @server = socket, server
				@iv_key, @password = server.iv_key, server.password
				@packet_version = server.packet_version
				@packet_length = @packet_version::PACK_LENGTH
				@socket.write [@iv_key, Time.now.to_i].pack( 'a* L>')
			end

			def fetch
				data = read
				@packet_version.parse data, @iv_key, @password  if data
			end

			def eof?() @socket.eof? end
			def read() @socket.read @packet_length end
			def close() @socket.close end
		end
	end
end
