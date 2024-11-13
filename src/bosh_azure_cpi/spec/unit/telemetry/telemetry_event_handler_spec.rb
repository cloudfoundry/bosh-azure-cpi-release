# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::TelemetryEventHandler do
  describe '#collect_and_send_events' do
    let(:logger) { instance_double(Logger) }
    let(:wire_client) { instance_double(Bosh::AzureCloud::WireClient) }
    let(:event_handler) { Bosh::AzureCloud::TelemetryEventHandler.new(logger) }

    before do
      allow(Bosh::AzureCloud::WireClient).to receive(:new).and_return(wire_client)
    end

    context 'when it gets the lock successfully' do
      before do
        allow_any_instance_of(File).to receive(:flock).with(File::LOCK_EX | File::LOCK_NB).and_return(0)
        allow_any_instance_of(File).to receive(:flock).with(File::LOCK_UN)
        allow(event_handler).to receive(:has_event?).and_return(true, false) # has_event? must return false at the end to terminate the while loop
      end

      context 'when the last post happened less than 1 minutes ago' do
        let(:now) { Time.new.round }
        let(:last_post_timestamp) { now - 59 }

        before do
          allow(Time).to receive(:new).and_return(now)
          allow(event_handler).to receive(:get_last_post_timestamp).and_return(last_post_timestamp)
        end

        it 'will sleep and then handle the events' do
          expect(event_handler).to receive(:sleep).with(1)
          expect(event_handler).to receive(:collect_events).once
          expect(event_handler).to receive(:send_events).once
          expect(event_handler).to receive(:update_last_post_timestamp).once
          expect do
            event_handler.collect_and_send_events
          end.not_to raise_error
        end
      end

      context 'when the last post happened more than 1 minutes ago' do
        let(:now) { Time.new.round }
        let(:last_post_timestamp) { now - 61 }

        before do
          allow(Time).to receive(:new).and_return(now)
          allow(event_handler).to receive(:get_last_post_timestamp).and_return(last_post_timestamp)
        end

        it 'will handle the events' do
          expect(event_handler).not_to receive(:sleep)
          expect(event_handler).to receive(:collect_events).once
          expect(event_handler).to receive(:send_events).once
          expect(event_handler).to receive(:update_last_post_timestamp).once
          expect do
            event_handler.collect_and_send_events
          end.not_to raise_error
        end
      end
    end

    context 'when it fails to get the lock' do
      before do
        allow_any_instance_of(File).to receive(:flock).with(File::LOCK_EX | File::LOCK_NB).and_return(false)
      end

      it 'will quit silently' do
        expect(event_handler).not_to receive(:has_event?)
        expect do
          event_handler.collect_and_send_events
        end.not_to raise_error
      end
    end
  end

  describe '#has_event?' do
    let(:logger) { instance_double(Logger) }
    let(:wire_client) { instance_double(Bosh::AzureCloud::WireClient) }
    let(:event_handler) { Bosh::AzureCloud::TelemetryEventHandler.new(logger) }

    let(:cpi_events_dir) { Bosh::AzureCloud::Helpers::CPI_EVENTS_DIR }

    before do
      allow(Bosh::AzureCloud::WireClient).to receive(:new).and_return(wire_client)
      FileUtils.mkdir_p(cpi_events_dir)
    end

    after do
      Dir.delete(cpi_events_dir) if Dir.exist?(cpi_events_dir)
    end

    context 'when it has event files' do
      let(:event_file) { "#{cpi_events_dir}/has-events-test.tld" }

      before do
        File.new(event_file, 'w')
      end

      after do
        File.delete(event_file)
      end

      it 'should return true' do
        expect(event_handler.send(:has_event?)).to be true
      end
    end
  end

  describe '#collect_events' do
    let(:logger) { instance_double(Logger) }
    let(:wire_client) { instance_double(Bosh::AzureCloud::WireClient) }
    let(:cpi_events_dir) { '/tmp/azure_cpi_test_collect_events' }
    let(:event_handler) { Bosh::AzureCloud::TelemetryEventHandler.new(logger, cpi_events_dir) }

    let(:json) do
      {
        'eventId' => 'fake-event-id',
        'providerId' => 'fake-provider-id',
        'parameters' => [
          {
            'name' => 'fake-name1',
            'value' => 'fake-value1'
          },
          {
            'name' => 'fake-name2',
            'value' => 'fake-value2'
          }
        ]
      }.to_json
    end

    let(:event_number) { 2 }

    before do
      allow(Bosh::AzureCloud::WireClient).to receive(:new).and_return(wire_client)
      FileUtils.mkdir_p(cpi_events_dir)

      (0...event_number).each do |number|
        File.open("#{cpi_events_dir}/collect-events-test-#{number}.tld", 'w') do |file|
          file.write(json)
        end
      end
    end

    after do
      Dir.delete(cpi_events_dir) if Dir.exist?(cpi_events_dir)
    end

    context 'if everything is is ok' do
      it 'should collect events' do
        expect(JSON).to receive(:parse).and_call_original.twice
        expect(Bosh::AzureCloud::TelemetryEvent).to receive(:parse_hash).and_call_original.twice
        expect(File).to receive(:delete).and_call_original.twice
        expect do
          event_handler.send(:collect_events, event_number)
        end.not_to raise_error
      end
    end

    context 'if error happens' do
      let(:event_number) { 1 }

      it 'should raise the error' do
        expect(JSON).to receive(:parse).and_raise 'unknown error'
        expect(Bosh::AzureCloud::TelemetryEvent).not_to receive(:parse_hash)
        expect(File).to receive(:delete).and_call_original
        expect(logger).to receive(:warn).with(/unknown error/)
        expect do
          event_handler.send(:collect_events, event_number)
        end.to raise_error(/unknown error/)
      end
    end
  end

  describe '#send_events' do
    let(:logger) { instance_double(Logger) }
    let(:wire_client) { instance_double(Bosh::AzureCloud::WireClient) }
    let(:event_handler) { Bosh::AzureCloud::TelemetryEventHandler.new(logger) }

    let(:event_list) { double('event-list') }

    before do
      allow(Bosh::AzureCloud::WireClient).to receive(:new).and_return(wire_client)
    end

    it 'should send the events' do
      expect(wire_client).to receive(:post_data).with(event_list)
      expect do
        event_handler.send(:send_events, event_list)
      end.not_to raise_error
    end
  end

  describe '#get_last_post_timestamp' do
    let(:logger) { instance_double(Logger) }
    let(:event_handler) { Bosh::AzureCloud::TelemetryEventHandler.new(logger) }
    let(:timestamp_file) { Bosh::AzureCloud::Helpers::CPI_EVENT_HANDLER_LAST_POST_TIMESTAMP }

    let(:time) { Time.new.round }

    context 'when file exists' do
      before do
        File.open(timestamp_file, 'w') do |file|
          file.write(time)
        end
      end

      after do
        File.delete(timestamp_file)
      end

      it 'should return correct value' do
        expect(event_handler.send(:get_last_post_timestamp)).to eq(time)
      end
    end

    context 'when file does not exist' do
      before do
        File.delete(timestamp_file) if File.exist?(timestamp_file)
      end

      it 'should return nil' do
        expect(event_handler.send(:get_last_post_timestamp)).to be nil
      end
    end
  end

  describe '#update_last_post_timestamp' do
    let(:logger) { instance_double(Logger) }
    let(:event_handler) { Bosh::AzureCloud::TelemetryEventHandler.new(logger) }
    let(:timestamp_file) { Bosh::AzureCloud::Helpers::CPI_EVENT_HANDLER_LAST_POST_TIMESTAMP }

    let(:time) { Time.new.round }

    after do
      File.delete(timestamp_file)
    end

    it 'should update the last post timestamp' do
      expect_any_instance_of(File).to receive(:write).with(time.to_s)
      expect do
        event_handler.send(:update_last_post_timestamp, time)
      end.not_to raise_error
    end
  end
end
