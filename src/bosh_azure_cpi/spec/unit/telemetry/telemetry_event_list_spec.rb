# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::TelemetryEventList do
  describe '#initialize' do
    context 'when event_list is an Array' do
      let(:param) { [] }
      it 'should not raise an error' do
        expect do
          Bosh::AzureCloud::TelemetryEventList.new(param)
        end.not_to raise_error
      end
    end

    context 'when event_list is not an Array' do
      let(:param) { nil }
      it 'should raise an error' do
        expect do
          Bosh::AzureCloud::TelemetryEventList.new(param)
        end.to raise_error /event_list must be an Array/
      end
    end
  end

  describe '#length' do
    let(:parameter1) { Bosh::AzureCloud::TelemetryEventParam.new('fake-name1', 'fake-value1') }
    let(:parameter2) { Bosh::AzureCloud::TelemetryEventParam.new('fake-name2', 'fake-value2') }
    let(:event1) { Bosh::AzureCloud::TelemetryEvent.new('fake-event-id', 'fake-provider-id', parameters: [parameter1, parameter2]) }
    let(:event2) { Bosh::AzureCloud::TelemetryEvent.new('fake-event-id', 'fake-provider-id', parameters: [parameter1, parameter2]) }

    let(:event_list) { Bosh::AzureCloud::TelemetryEventList.new([event1, event2]) }

    it 'should return with right value' do
      expect(event_list.length).to eq(2)
    end
  end

  describe '#format_data_for_wire_server' do
    let(:parameter1) { Bosh::AzureCloud::TelemetryEventParam.new('fake-name1', 'fake-value1') }
    let(:parameter2) { Bosh::AzureCloud::TelemetryEventParam.new('fake-name2', 'fake-value2') }
    let(:event1) { Bosh::AzureCloud::TelemetryEvent.new('fake-event-id', 'fake-provider-id', parameters: [parameter1, parameter2]) }
    let(:event2) { Bosh::AzureCloud::TelemetryEvent.new('fake-event-id', 'fake-provider-id', parameters: [parameter1, parameter2]) }

    let(:event_list) { Bosh::AzureCloud::TelemetryEventList.new([event1, event2]) }

    it 'should return with right value' do
      expect(event_list.format_data_for_wire_server).to eq('<?xml version="1.0"?><TelemetryData version="1.0"><Provider id="fake-provider-id"><Event id="fake-event-id"><![CDATA[<Param Name="fake-name1" Value="fake-value1" T="mt:wstr" /><Param Name="fake-name2" Value="fake-value2" T="mt:wstr" />]]></Event><Event id="fake-event-id"><![CDATA[<Param Name="fake-name1" Value="fake-value1" T="mt:wstr" /><Param Name="fake-name2" Value="fake-value2" T="mt:wstr" />]]></Event></Provider></TelemetryData>')
    end
  end
end
