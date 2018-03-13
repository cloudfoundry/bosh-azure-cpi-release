require 'spec_helper'

describe Bosh::AzureCloud::TelemetryEventParam do
  describe "#parse_hash" do
    let(:hash) {
      {
        "name" => "fake-name",
        "value" => "fake-value"
      }
    }

    it "should parse the hash and create an instance" do
      expect(Bosh::AzureCloud::TelemetryEventParam).to receive(:new).
        with(hash["name"], hash["value"])

      expect{
        Bosh::AzureCloud::TelemetryEventParam.parse_hash(hash)
      }.not_to raise_error
    end
  end

  describe "#to_hash" do
    let(:hash) {
      {
        "name" => "fake-name",
        "value" => "fake-value"
      }
    }

    let(:telemetry_event_param) { Bosh::AzureCloud::TelemetryEventParam.new("fake-name", "fake-value") }

    it "should return with right value" do
      expect(telemetry_event_param.to_hash).to eq(hash)
    end
  end

  describe "#to_json" do
    let(:json) {
      {
        "name" => "fake-name",
        "value" => "fake-value"
      }.to_json
    }

    let(:telemetry_event_param) { Bosh::AzureCloud::TelemetryEventParam.new("fake-name", "fake-value") }

    it "should return with right value" do
      expect(telemetry_event_param.to_json).to eq(json)
    end
  end

  describe "#to_xml" do
    context "when value is a string" do
      let(:telemetry_event_param) { Bosh::AzureCloud::TelemetryEventParam.new("fake-name", "fake-value") }

      it "should return with right value" do
        expect(telemetry_event_param.to_xml).to eq("<Param Name=\"fake-name\" Value=\"fake-value\" T=\"mt:wstr\" />")
      end
    end

    context "when value is a hash" do
      let(:telemetry_event_param) { Bosh::AzureCloud::TelemetryEventParam.new("fake-name", {"fake-key" => "fake-value"}) }

      it "should return with right value" do
        expect(telemetry_event_param.to_xml).to eq("<Param Name=\"fake-name\" Value=\"{&quot;fake-key&quot;:&quot;fake-value&quot;}\" T=\"mt:wstr\" />")
      end
    end
  end

  describe "#type_of" do
    let(:telemetry_event_param) { Bosh::AzureCloud::TelemetryEventParam.new("fake-name", "fake-value") }

    context "when value is a string" do
      it "should return with right value" do
        expect(telemetry_event_param.send(:type_of, 'string')).to eq("mt:wstr")
      end
    end

    context "when value is a integer" do
      it "should return with right value" do
        expect(telemetry_event_param.send(:type_of, 0)).to eq("mt:uint64")
      end
    end

    context "when value is a float" do
      it "should return with right value" do
        expect(telemetry_event_param.send(:type_of, 0.1)).to eq("mt:float64")
      end
    end

    context "when value is a bool" do
      it "should return with right value" do
        expect(telemetry_event_param.send(:type_of, true)).to eq("mt:bool")
        expect(telemetry_event_param.send(:type_of, false)).to eq("mt:bool")
      end
    end

    context "when value is a hash" do
      it "should return with right value" do
        expect(telemetry_event_param.send(:type_of, {})).to eq("mt:wstr")
      end
    end

    context "when type of value is unknown" do
      let(:obj) { double('unknown-type') }
      it "should return with right value" do
        expect(telemetry_event_param.send(:type_of, obj)).to eq("mt:wstr")
      end
    end
  end
end
