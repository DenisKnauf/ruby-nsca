require 'socket'
require 'enum'
require 'timeout'
require 'benchmark'
require 'securerandom'

module NSCA
	class ReturnCode <Enum
		start_at 0
		enum %w[OK WARNING CRITICAL UNKNOWN]
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
		def destinations()  @destinations ||= []  end

		def send *results
			NSCA.destinations.each {|server| server.send *results }
			self
		end
	end
end

require 'lib/packet'
require 'lib/server'
require 'lib/client'
require 'lib/check'
