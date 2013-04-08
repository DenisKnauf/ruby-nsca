module NSCA
	class <<self
		def xor key, msg, key_a = nil
			key_a ||= key.unpack 'C*'
			l = key_a.length
			return msg  if l < 1
			# Slice the message in parts of length key_a.length.
			# XOR each char of a part with char at the same index in key_a.
			msg.unpack( 'C*').each_with_index.map {|c,i| c^key_a[i%l] }.pack 'C*'
		end

		def crc32 msg
			(msg.each_byte.inject 0xFFFFFFFF do |r,b|
				8.times.inject( r^b) {|r,_i| (r>>1) ^ (0xEDB88320 * (r&1)) }
			end) ^ 0xFFFFFFFF
		end

		# Builds a null terminated, null padded string of length maxlen
		def str2cstr( str, maxlen = nil)
			str = str.to_s
			str = str.to_s[0..(maxlen-2)]  if maxlen
			"#{str}\x00"
		end
		def cstr2str( str, maxlen = nil) str[ 0, x.index( ?\0) || ((maxlen||0)-1)]  end
	end

	class Packet
		class CSC32CheckFailed <Exception
		end
		class VersionCheckFailed <Exception
		end

		def self.versions version = nil
			@@versions ||= {}
			version ? @@versions[version] : @@versions
		end

		def self.register_version( version, klass) versions[version] = klass end

		# @param [Time,Integer,nil] timestamp Checked at this time
		# @param [0..3] return_code `NSCA::ReturnCode`
		# @param [String(length<64),nil] hostname If nil, local hostname will be used.
		#                                         Must be known by Nagios.
		# @param [String(length<128)] service Name of Service. Must be known by Nagios.
		# @param [String(length<512)] status Status-line inclusive optional Performance Data.
		def initialize timestamp, return_code, hostname, service, status
			@timestamp, @return_code, @hostname, @service, @status =
				Time.at( timestamp.to_f), return_code, hostname, service, status
		end

		attr_accessor :timestamp, :return_code, :hostname, :service, :status
	end

	class PacketV3 < Packet
		NAGIOS_VERSION = 2.7
		PACKET_VERSION = 3
		END_OF_TRANSMISSION = ?\x0a
		HOSTNAME_LENGTH = 64
		SERVICE_LENGTH = 128
		STATUS_LENGTH = 512

		# these line describes the data package:
		# typedef struct data_packet_struct{
		#   int16_t   packet_version;
		#   /* two padding bytes (because aligning): xx */
		#   u_int32_t crc32_value;
		#   u_int32_t timestamp;
		#   int16_t   return_code;
		#   char      host_name[MAX_HOSTNAME_LENGTH];
		#   char      svc_description[MAX_DESCRIPTION_LENGTH];
		#   char      plugin_output[MAX_PLUGINOUTPUT_LENGTH];
		#   /* two extra padding-xx, too. */
		# }data_packet;
		PACK_STRING = "s> xx L> L> s> Z#{HOSTNAME_LENGTH} Z#{SERVICE_LENGTH} Z#{STATUS_LENGTH} xx"
		PACK_LENGTH = 2+2+4+4+2+HOSTNAME_LENGTH+SERVICE_LENGTH+STATUS_LENGTH+2
		register_version PACKET_VERSION, self

		# Builds a check-result-line for NSCA.
		#
		# Will be terminated by end-of-terminate.
		def build key = nil, password = nil
			entry = [
				PACKET_VERSION,
				0, # crc32 (unknown yet)
				(timestamp || Time.now).to_i,
				return_code.to_i,
				NSCA::str2cstr( hostname || `hostname -f`, HOSTNAME_LENGTH),
				NSCA::str2cstr( service, SERVICE_LENGTH),
				NSCA::str2cstr( status, STATUS_LENGTH) # incl perfdata
			]
			# generate crc32 and put it at entry[2...6]
			entry[1] = NSCA::crc32 entry.pack( PACK_STRING)
			entry = entry.pack PACK_STRING
			entry = NSCA::xor key, entry  if key
			entry = NSCA::xor password, entry  if password
			entry
		end

		def self.parse entry, key = nil, password = nil, no_verification_checks = nil
			entry = NSCA::xor key, entry  if key
			entry = NSCA::xor password, entry  if password
			ver, crc32sum, *x = entry.unpack( PACK_STRING)
			raise VersionCheckFailed, "Packet version 3 expected. (recv: #{ver})" \
				unless no_verification_checks or 3 == ver
			entry[4..7] = ?\x00*4
			raise CSC32CheckFailed, "crc32-check failed. packet seems to be broken." \
				unless no_verification_checks or crc32sum == NSCA::crc32( entry)
			new *x
		end
	end
end
