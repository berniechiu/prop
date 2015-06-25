require_relative 'helper'

describe Prop::Limiter do
  before do
    @store = {}
    @cache_key = "cache_key"

    Prop::Limiter.read  { |key| @store[key] }
    Prop::Limiter.write { |key, value| @store[key] = value }

    @start = Time.now
    Time.stubs(:now).returns(@start)
  end

  describe "BaseStrategy" do
    before do
      Prop::Limiter.configure(:something, :threshold => 10, :interval => 10)
      Prop::BaseStrategy.stubs(:build).returns(@cache_key)
      Prop.reset(:something)
    end

    after do
      @store.delete(@cache_key)
    end

    describe "#throttle" do
      describe "when disabled" do
        before { Prop::Limiter.stubs(:disabled?).returns(true) }

        it "returns nil" do
          assert_nil Prop.throttle(:something)
        end
      end

      describe "when not disabled" do
        before { Prop::Limiter.stubs(:disabled?).returns(false) }

        describe "and the threshold has been reached" do
          before { Prop::BaseStrategy.stubs(:at_threshold?).returns(true) }

          it "returns true" do
            assert Prop.throttle(:something)
          end

          it "does not increment the throttle count" do
            Prop.throttle(:something)

            assert_equal 0, Prop.count(:something)
          end

          describe "when given a block" do
            before { @test_block_executed = false }

            it "does not execute the block" do
              Prop.throttle(:something) { @test_block_executed = true }

              refute @test_block_executed
            end
          end

          describe "when a before_throttle callback has been specified" do
            before do
              Prop.before_throttle do |handle, key, threshold, interval|
                @handle    = handle
                @key       = key
                @threshold = threshold
                @interval  = interval
              end

              Prop.throttle(:something, [:extra])
            end

            it "invokes callback with expected parameters" do
              assert_equal @handle, :something
              assert_equal @key, [:extra]
              assert_equal @threshold, 10
              assert_equal @interval, 10
            end
          end
        end

        describe "and the threshold has not been reached" do
          before { Prop::BaseStrategy.stubs(:at_threshold?).returns(false) }

          it "returns false" do
            refute Prop.throttle(:something)
          end

          it "increments the throttle count by one" do
            Prop.throttle(:something)

            assert_equal 1, Prop.count(:something)
          end

          it "increments the throttle count by the specified number when provided" do
            Prop.throttle(:something, nil, :increment => 5)

            assert_equal 5, Prop.count(:something)
          end

          describe "when given a block" do
            before { @test_block_executed = false }

            it "executes the block" do
              Prop.throttle(:something) { @test_block_executed = true }

              assert @test_block_executed
            end
          end
        end
      end
    end

    describe "#throttle!" do
      it "throttles the given handle/key combination" do
        Prop::Limiter.expects(:throttle).with(
          :something,
          :key,
          {
            :threshold => 10,
            :interval  => 10,
            :key       => 'key',
            :strategy  => Prop::BaseStrategy,
            :options   => true
          }
        )

        Prop.throttle!(:something, :key, :options => true)
      end

      describe "when the threshold has been reached" do
        before { Prop::Limiter.stubs(:throttle).returns(true) }

        it "raises a rate-limited exception" do
          assert_raises(Prop::RateLimited) { Prop.throttle!(:something) }
        end

        describe "when given a block" do
          before { @test_block_executed = false }

          it "does not executes the block" do
            begin
              Prop.throttle!(:something) { @test_block_executed = true }
            rescue Prop::RateLimited
              refute @test_block_executed
            end
          end
        end
      end

      describe "when the threshold has not been reached" do
        it "returns the counter value" do
          assert_equal Prop.count(:something) + 1, Prop.throttle!(:something)
        end

        describe "when given a block" do
          it "returns the return value of the block" do
            assert_equal 'block_value', Prop.throttle!(:something) { 'block_value' }
          end
        end
      end
    end
  end

  describe "LeakyBucketStrategy" do
    before do
      Prop::Limiter.configure(:something, :threshold => 10, :interval => 1, :burst_rate => 100, :strategy => :leaky_bucket)
      Prop::LeakyBucketStrategy.stubs(:build).returns(@cache_key)
    end

    after do
      @store.delete(@cache_key)
    end

    describe "#throttle" do
      describe "when the bucket is not full" do
        it "increments the count number and saves timestamp in the bucket" do
          bucket_expected = { :bucket => 1, :last_updated => @start.to_i }
          assert !Prop::Limiter.throttle(:something)
          assert_equal bucket_expected, @store[@cache_key]
        end
      end

      describe "when the bucket is full" do
        before do
          @store[@cache_key] = { :bucket => 100, :last_updated => @start.to_i }
        end

        it "returns true and doesn't increment the count number in the bucket" do
          bucket_expected = { :bucket => 100, :last_updated => @start.to_i }
          assert Prop::Limiter.throttle(:something)
          assert_equal bucket_expected, @store[@cache_key]
        end
      end
    end

    describe "#throttle!" do
      it "throttles the given handle/key combination" do
        Prop::Limiter.expects(:throttle).with(
          :something,
          :key,
          {
              :threshold    => 10,
              :interval     => 1,
              :key          => 'key',
              :burst_rate   => 100,
              :strategy     => Prop::LeakyBucketStrategy,
              :options      => true
          }
        )

        Prop::Limiter.throttle!(:something, :key, :options => true)
      end

      describe "when the bucket is full" do
        before do
          Prop::Limiter.expects(:throttle).returns(true)
        end

        it "raises RateLimited exception" do
          assert_raises Prop::RateLimited do
            Prop::Limiter.throttle!(:something)
          end
        end
      end

      describe "when the bucket is not full" do
        it "returns the bucket" do
          expected_bucket = { :bucket => 1, :last_updated => @start.to_i }
          assert_equal expected_bucket, Prop::Limiter.throttle!(:something)
        end
      end
    end
  end
end
