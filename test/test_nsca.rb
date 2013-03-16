require 'helper'

class TestNSCA < Test::Unit::TestCase
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
		NSCA::PerformanceData.new 'subclass test'
		assert_nothing_raised NameError do
			assert NSCA::PerformanceData::Subclass_test, "No subclass created."
		end
	end

	def perfdata *a
		NSCA::PerformanceData.create *a
	end

	context 'Created NSCA::PerformanceData-subclasses' do
		should 'be the same like returned' do
			cl = NSCA::PerformanceData.new 'returned and subclass the same test'
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


class TestNSCA::Connection < Test::Unit::TestCase
	should '' do
		NSCA::Connection
	end
end
