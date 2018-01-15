require 'spec_helper'

describe Bosh::AzureCloud::TelemetryEventList do
  describe "#format_data_for_wire_server" do
    let(:parameter1) { Bosh::AzureCloud::TelemetryEventParam.new("fake-name1", "fake-value1") }
    let(:parameter2) { Bosh::AzureCloud::TelemetryEventParam.new("fake-name2", "fake-value2") }
    let(:event1) { Bosh::AzureCloud::TelemetryEvent.new("fake-event-id", "fake-provider-id", parameters: [parameter1, parameter2]) }
    let(:event2) { Bosh::AzureCloud::TelemetryEvent.new("fake-event-id", "fake-provider-id", parameters: [parameter1, parameter2]) }

    let(:event_list) { Bosh::AzureCloud::TelemetryEventList.new([event1, event2]) }

    it "should return with right value" do
      expect(event_list.format_data_for_wire_server).to eq("<?xml version=\"1.0\"?><TelemetryData version=\"1.0\"><Provider id=\"fake-provider-id\"><Event id=\"fake-event-id\"><![CDATA[<Param Name=\"fake-name1\" Value=\"fake-value1\" T=\"mt:wstr\" /><Param Name=\"fake-name2\" Value=\"fake-value2\" T=\"mt:wstr\" />]]></Event><Event id=\"fake-event-id\"><![CDATA[<Param Name=\"fake-name1\" Value=\"fake-value1\" T=\"mt:wstr\" /><Param Name=\"fake-name2\" Value=\"fake-value2\" T=\"mt:wstr\" />]]></Event></Provider></TelemetryData>")
    end
  end
end

