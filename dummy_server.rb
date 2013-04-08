require 'socket'

module NSCA
	class ServerDummy
		attr_reader :server
		def initialize *host_and_port
			@server = TCPServer.new *host_and_port
		end
	end
end
