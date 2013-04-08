module NSCA
	def self.dummy_server port, password = nil, key = nil
		require 'pathname'
		load Pathname.new( __FILE__).dirname.join( '..', 'lib', 'nsca.rb').to_s
		serv = NSCA::Server.new port, password: password, key: key
		sock = serv.accept
		sock.fetch
	ensure
		sock.close  if sock
		serv.close  if serv
	end
end
