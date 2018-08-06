# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::TelemetryManager do
  describe '#monitor' do
    let(:logger) { instance_double(Bosh::Cpi::Logger) }
    let(:telemetry_event) { instance_double(Bosh::AzureCloud::TelemetryEvent) }

    let(:id) { 'fake-id' }
    let(:operation) { 'fake-op' }
    let(:extras) { { 'fake-key' => 'fake-value' } }

    let(:event_param_name) { instance_double(Bosh::AzureCloud::TelemetryEventParam) }
    let(:event_param_version) { instance_double(Bosh::AzureCloud::TelemetryEventParam) }
    let(:event_param_operation) { instance_double(Bosh::AzureCloud::TelemetryEventParam) }
    let(:event_param_container_id) { instance_double(Bosh::AzureCloud::TelemetryEventParam) }
    let(:event_param_operation_success) { instance_double(Bosh::AzureCloud::TelemetryEventParam) }
    let(:event_param_message) { instance_double(Bosh::AzureCloud::TelemetryEventParam) }
    let(:event_param_duration) { instance_double(Bosh::AzureCloud::TelemetryEventParam) }

    before do
      allow(Bosh::Cpi::Logger).to receive(:new).and_return(logger)

      allow(Bosh::AzureCloud::TelemetryEventParam).to receive(:new)
        .with('Name', 'BOSH-CPI')
        .and_return(event_param_name)
      allow(Bosh::AzureCloud::TelemetryEventParam).to receive(:new)
        .with('Version', Bosh::AzureCloud::VERSION)
        .and_return(event_param_version)
      allow(Bosh::AzureCloud::TelemetryEventParam).to receive(:new)
        .with('Operation', operation)
        .and_return(event_param_operation)
      allow(Bosh::AzureCloud::TelemetryEventParam).to receive(:new)
        .with('ContainerId', id)
        .and_return(event_param_container_id)
      allow(Bosh::AzureCloud::TelemetryEventParam).to receive(:new)
        .with('OperationSuccess', true)
        .and_return(event_param_operation_success)
      allow(Bosh::AzureCloud::TelemetryEventParam).to receive(:new)
        .with('Message', '')
        .and_return(event_param_message)
      allow(Bosh::AzureCloud::TelemetryEventParam).to receive(:new)
        .with('Duration', 0)
        .and_return(event_param_duration)

      allow(event_param_duration).to receive(:value=)
      allow(event_param_message).to receive(:value=)

      allow(Bosh::AzureCloud::TelemetryEvent).to receive(:new)
        .and_return(telemetry_event)
      allow(telemetry_event).to receive(:add_param).with(event_param_name)
      allow(telemetry_event).to receive(:add_param).with(event_param_version)
      allow(telemetry_event).to receive(:add_param).with(event_param_operation)
      allow(telemetry_event).to receive(:add_param).with(event_param_container_id)
      allow(telemetry_event).to receive(:add_param).with(event_param_operation_success)
      allow(telemetry_event).to receive(:add_param).with(event_param_message)
      allow(telemetry_event).to receive(:add_param).with(event_param_duration)
    end

    context 'when the block is executed successfully' do
      let(:telemetry_manager) { Bosh::AzureCloud::TelemetryManager.new(mock_azure_config_merge('enable_telemetry' => true)) }
      let(:result) { 'fake-result' }

      context 'when operation is not initialize' do
        it 'should return the result and report the event' do
          expect(event_param_message).to receive(:value=)
            .with('msg' => 'Successed',
                  'subscription_id' => mock_azure_config.subscription_id,
                  'fake-key' => 'fake-value')
          expect(telemetry_manager).to receive(:report_event)

          expect(
            telemetry_manager.monitor(operation, id: id, extras: extras) do
              result
            end
          ).to eq(result)
        end
      end

      context 'when operation is initialize' do
        let(:operation) { 'initialize' }

        it 'should return the result but do not report the event' do
          expect(event_param_message).to receive(:value=)
            .with('msg' => 'Successed',
                  'subscription_id' => mock_azure_config.subscription_id,
                  'fake-key' => 'fake-value')
          expect(telemetry_manager).not_to receive(:report_event)

          expect(
            telemetry_manager.monitor(operation, id: id, extras: extras) do
              result
            end
          ).to eq(result)
        end
      end
    end

    context 'when the block raises an error' do
      let(:telemetry_manager) { Bosh::AzureCloud::TelemetryManager.new(mock_azure_config_merge('enable_telemetry' => true)) }

      context 'when length of the message exceeds 3.9 kB' do
        let(:error) { 'x' * 3994 }
        let(:runtime_error_prefix) { '#<RuntimeError: ' }
        let(:error_message) { "#{runtime_error_prefix}#{error}"[0...3990] + '...' }

        it 'should raise the entire error message and send the truncated message for telemetry' do
          expect(event_param_operation_success).to receive(:value=)
            .with(false)
          expect(event_param_message).to receive(:value=)
            .with(hash_including('msg' => error_message))
          expect(telemetry_manager).to receive(:report_event)

          expect do
            telemetry_manager.monitor(operation, id: id, extras: extras) do
              raise error
            end
          end.to raise_error error
        end
      end

      context 'when length of the message does not exceed 3.9 kB' do
        let(:error) { 'x' }
        let(:runtime_error_prefix) { '#<RuntimeError: ' }
        let(:error_message) { "#{runtime_error_prefix}#{error}" }

        it 'should raise the error and report the event' do
          expect(event_param_operation_success).to receive(:value=)
            .with(false)
          expect(event_param_message).to receive(:value=)
            .with(hash_including('msg' => /#{error_message}/))
          expect(telemetry_manager).to receive(:report_event)

          expect do
            telemetry_manager.monitor(operation, id: id, extras: extras) do
              raise error
            end
          end.to raise_error error
        end
      end

      context 'operation is initialize' do
        let(:error) { 'x' }
        let(:runtime_error_prefix) { '#<RuntimeError: ' }
        let(:error_message) { "#{runtime_error_prefix}#{error}" }
        let(:operationi) { 'initialize' }

        it 'should raise the error and report the event' do
          expect(event_param_operation_success).to receive(:value=)
            .with(false)
          expect(event_param_message).to receive(:value=)
            .with(hash_including('msg' => /#{error_message}/))
          expect(telemetry_manager).to receive(:report_event)

          expect do
            telemetry_manager.monitor(operation, id: id, extras: extras) do
              raise error
            end
          end.to raise_error error
        end
      end
    end

    context 'when telemetry is not enabled' do
      let(:telemetry_manager) { Bosh::AzureCloud::TelemetryManager.new(mock_azure_config_merge('enable_telemetry' => false)) }
      let(:result) { 'fake-result' }

      it 'should return the result and does not report the event' do
        expect(telemetry_manager).not_to receive(:report_event)

        expect(
          telemetry_manager.monitor(operation, id: id, extras: extras) do
            result
          end
        ).to eq(result)
      end
    end
    context 'when environment is AzureStack' do
      let(:telemetry_manager) { Bosh::AzureCloud::TelemetryManager.new(mock_azure_config_merge('enable_telemetry' => true, 'environment' => 'AzureStack')) }
      let(:result) { 'fake-result' }

      it 'should return the result and does not report the event' do
        expect(telemetry_manager).not_to receive(:report_event)

        expect(
          telemetry_manager.monitor(operation, id: id, extras: extras) do
            result
          end
        ).to eq(result)
      end
    end
  end

  describe '#report_event' do
    let(:logger) { instance_double(Bosh::Cpi::Logger) }
    let(:telemetry_manager) { Bosh::AzureCloud::TelemetryManager.new(mock_azure_config) }
    let(:telemetry_event) { instance_double(Bosh::AzureCloud::TelemetryEvent) }
    let(:telemetry_event_handler) { instance_double(Bosh::AzureCloud::TelemetryEventHandler) }
    let(:file) { double('file') }
    let(:event_handler) { instance_double(Bosh::AzureCloud::TelemetryEventHandler) }

    before do
      allow(Bosh::Cpi::Logger).to receive(:new).and_return(logger)
      allow(Bosh::AzureCloud::TelemetryEventHandler).to receive(:new).and_return(event_handler)
    end

    context 'when everything is ok' do
      before do
        allow(Open3).to receive(:capture3).and_return(['fake-stdout', 'fake-stderr', 0])
        allow(telemetry_event).to receive(:to_json).and_return('fake-event')
        allow(logger).to receive(:warn)
      end

      it 'should collect and sent events' do
        expect(File).to receive(:open).and_call_original do |file|
          expect(file).to receive(:write)
        end

        expect(telemetry_manager).to receive(:fork).and_call_original do |_block1|
          expect(Process).to receive(:setsid)
          expect(STDIN).to receive(:reopen)
          expect(STDOUT).to receive(:reopen)
          expect(STDERR).to receive(:reopen)

          expect(telemetry_manager).to receive(:fork).and_call_original do |_block2|
            expect(event_handler).to receive(:collect_and_send_events)
          end
        end

        expect do
          telemetry_manager.send(:report_event, telemetry_event)
        end.not_to raise_error
      end
    end

    context 'when it fails to move event file to CPI_EVENTS_DIR' do
      let(:err_status) { 1 }

      before do
        allow(Open3).to receive(:capture3).and_return(['fake-stdout', 'fake-stderr', err_status])
        allow(telemetry_event).to receive(:to_json).and_return('fake-event')
      end

      it 'should log the error and drop it silently' do
        expect(File).to receive(:open).and_call_original do |file|
          expect(file).to receive(:write)
        end
        expect(logger).to receive(:warn).with(/fake-stderr/)
        expect(Bosh::AzureCloud::TelemetryEventHandler).not_to receive(:new)

        expect do
          telemetry_manager.send(:report_event, telemetry_event)
        end.not_to raise_error
      end
    end

    context 'when exception is caught' do
      before do
        allow(File).to receive(:open).and_raise 'failed to open file'
      end

      it 'should log the error and drop the exception silently' do
        expect(logger).to receive(:warn).with(/failed to open file/)
        expect(Bosh::AzureCloud::TelemetryEventHandler).not_to receive(:new)

        expect do
          telemetry_manager.send(:report_event, telemetry_event)
        end.not_to raise_error
      end
    end
  end
end
