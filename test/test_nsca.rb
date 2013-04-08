require 'helper'

class TestNSCA < Test::Unit::TestCase
	class TestChecks
		extend NSCA::Checks
		perfdata :PD1, :pd1_in_sec, :s, 10, 20, 0, 30
		perfdata :PD2, :pd2_in_1, 1, 0.99, 0.98, 0, 1
		perfdata :PD3, :pd3_count, :c, 3, 5, 0
		check :T0, 'TestNSCA0', 'uxnags01-sbe.net.mobilkom.at'
		check :T1, 'TestNSCA1', 'uxnags01-sbe.net.mobilkom.at', [PD1, PD2]
		check :T2, :TestNSCA2, 'uxnags01-sbe.net.mobilkom.at', [PD1, PD2, PD3]
	end

	context 'our test server' do
		should 'receive data. NSCA-server should run on localhost 5777. if not, ignore this test. password=abcdefghijkl' do
			PD1 = TestChecks::PD1
			PD2 = TestChecks::PD2
			PD3 = TestChecks::PD3
			T0 = TestChecks::T0
			T1 = TestChecks::T1
			T2 = TestChecks::T2
			NSCA.destinations << NSCA::Client.new( 'localhost', 5667, password: 'abcdefghijkl')
			NSCA.send TestChecks::T0.new( 1, "0123456789"*51+"AB")

			return
			pd1 = PD1.new 3
			pd2 = PD2.new 0.9996
			pd3 = PD3.new 2
			NSCA.send TestChecks::T1.new( nil, "Should be OK", [pd1, pd2, pd3])
		end
	end
end

class TestNSCA::ReturnCode < Test::Unit::TestCase
	context 'return code' do
		should( 'be 0 == OK') { assert NSCA::ReturnCode.find(0) == NSCA::ReturnCode::OK }
		should( 'be 1 == WARNING') { assert NSCA::ReturnCode.find(1) == NSCA::ReturnCode::WARNING }
		should( 'be 2 == CRITICAL') { assert NSCA::ReturnCode.find(2) == NSCA::ReturnCode::CRITICAL }
		should( 'be 3 == UNKNOWN') { assert NSCA::ReturnCode.find(3) == NSCA::ReturnCode::UNKNOWN }
	end
end

class TestNSCA::Helper < Test::Unit::TestCase
	context 'class gen name' do
		should 'generate class names' do
			assert :Total_run_check_measure == NSCA::Helper.class_name_gen( 'total run check measure')
		end

		should 'do not generate class names, if no letter' do
			assert nil == NSCA::Helper.class_name_gen( '123 321, 43 _ ?')
		end
	end
end

class TestNSCA::PerformanceData < Test::Unit::TestCase
	should 'set a subclass for new PerfData-types' do
		NSCA::PerformanceData.create 'subclass test'
		assert_nothing_raised NameError do
			assert NSCA::PerformanceData::Subclass_test, "No subclass created."
		end
	end

	def perfdata *a
		NSCA::PerformanceData.new *a
	end

	context 'Created NSCA::PerformanceData-subclasses' do
		should 'be the same like returned' do
			cl = NSCA::PerformanceData.create 'returned and subclass the same test'
			assert cl == NSCA::PerformanceData::Returned_and_subclass_the_same_test, 'Classes are not the same.'
		end
		should 'have a unit if given' do
			assert :s == perfdata( 'have an unit test', :s).unit, "Not s as unit"
		end
		should 'have not a unit if not given' do
			assert nil == perfdata( 'have not an unit test', nil).unit, "Not nil as unit"
		end
		should 'have a warn thresh if given' do
			assert 3 == perfdata( 'have a warn test', nil, 3).warn, "Not 3 as warn"
		end
		should 'have not a warn thresh if not given' do
			assert nil == perfdata( 'have not a warn test', nil, nil).warn, "Not nil as warn"
		end
	end
end


class TestNSCA::Client < Test::Unit::TestCase
	should '' do
		NSCA::Client
	end
end
