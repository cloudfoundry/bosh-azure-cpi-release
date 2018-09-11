# frozen_string_literal: true

module Bosh::AzureCloud
  class TelemetryEventParam
    attr_writer :value

    PARAM_XML_FORMAT = '<Param Name="%{name}" Value=%{value} T="%{type}" />'

    def initialize(name, value)
      @name = name
      @value = value
    end

    def self.parse_hash(hash)
      new(hash['name'], hash['value'])
    end

    def to_hash
      { 'name' => @name, 'value' => @value }
    end

    def to_json
      to_hash.to_json
    end

    def to_xml
      value = @value.is_a?(Hash) ? @value.to_json : @value
      format(PARAM_XML_FORMAT, name: @name, value: value.to_s.encode(xml: :attr), type: type_of(@value))
    end

    private

    def type_of(value)
      case value
      when String
        'mt:wstr'
      when Integer
        'mt:uint64'
      when Float
        'mt:float64'
      when TrueClass
        'mt:bool'
      when FalseClass
        'mt:bool'
      when Hash
        'mt:wstr'
      else
        'mt:wstr'
      end
    end
  end

  # example:
  # @event = {
  #   "eventId" => 1,
  #   "providerId" => "69B669B9-4AF8-4C50-BDC4-6006FA76E975",
  #   "parameters" => [
  #     {
  #       "name" => "Name",
  #       "value" => "BOSH-CPI"
  #     },
  #     {
  #       "name" => "Version",
  #       "value" => ""
  #     }
  #   ]
  # }
  #
  # allowed parameters:
  #   "Name": "BOSH-CPI"
  #   "Version": string. CPI version.
  #   "Operation": string. CPI callback, e.g. create_vm, create_disk, attach_disk, etc
  #   "OperationSuccess": true / false. Operation status.
  #   "ContainerId": string
  #   "Duration": float. How long the operation takes.
  #   "Message": A JSON string contains info of
  #      "msg": "Successed" or error message
  #      "subscription_id": subscription id
  #      "vm_size": vm size. (optional)
  #      "disk_size": disk size. (optional)
  #
  class TelemetryEvent
    attr_reader :event_id, :provider_id, :parameters

    EVENT_XML_FORMAT = '<Provider id="%{provider_id}"><Event id="%{event_id}"><![CDATA[%{params_xml}]]></Event></Provider>'
    EVENT_XML_WITHOUT_PROVIDER_FORMAT = '<Event id="%{event_id}"><![CDATA[%{params_xml}]]></Event>'

    def initialize(event_id, provider_id, parameters: [])
      @event_id = event_id
      @provider_id = provider_id
      @parameters = parameters
    end

    def self.parse_hash(hash)
      parameters = []
      hash['parameters'].each do |p|
        parameters.push(TelemetryEventParam.parse_hash(p))
      end
      new(hash['eventId'], hash['providerId'], parameters: parameters)
    end

    def add_param(parameter)
      @parameters.push(parameter) if parameter.is_a?(TelemetryEventParam)
    end

    def to_hash
      parameters = []
      @parameters.each do |p|
        parameters.push(p.to_hash)
      end

      {
        'eventId' => @event_id,
        'providerId' => @provider_id,
        'parameters' => parameters
      }
    end

    def to_json
      to_hash.to_json
    end

    # this function is only used in TelemetryEventList which will group the events by provider_id
    def to_xml_without_provider
      params_xml = ''
      @parameters.each do |param|
        params_xml += param.to_xml
      end
      format(EVENT_XML_WITHOUT_PROVIDER_FORMAT, event_id: @event_id, params_xml: params_xml)
    end
  end

  class TelemetryEventList
    TELEMETRY_XML_FORMAT = '<?xml version="1.0"?><TelemetryData version="1.0">%{events_string}</TelemetryData>'
    EVENTS_WITH_PROVIDER_FORMAT = '<Provider id="%{provider_id}">%{event_xml_without_provider}</Provider>'

    def initialize(event_list)
      raise "event_list must be an Array, but it is a #{event_list.class}" unless event_list.is_a?(Array)

      @event_list = event_list
    end

    # example:
    # <?xml version="1.0"?><TelemetryData version="1.0"><Provider id="69B669B9-4AF8-4C50-BDC4-6006FA76E975"><Event id="1"><![CDATA[<Param Name="Name" Value="BOSH-CPI" T="mt:wstr" /><Param Name="Version" Value="" T="mt:wstr" /><Param Name="Operation" Value="create_vm" T="mt:wstr" /><Param Name="OperationSuccess" Value="True" T="mt:bool" /><Param Name="Message" Value='{"msg":"Successed"}' T="mt:wstr" /><Param Name="Duration" Value="510.046195" T="mt:float64" /><Param Name="OSVersion" Value="Linux:ubuntu-14.04-trusty:4.4.0-53-generic" T="mt:wstr" /><Param Name="GAVersion" Value="WALinuxAgent-2.1.3" T="mt:wstr" /><Param Name="RAM" Value="6958" T="mt:uint64" /><Param Name="Processors" Value="2" T="mt:uint64" /><Param Name="VMName" Value="_b9c3354c-3275-4049-680f-3748ad0af496" T="mt:wstr" /><Param Name="TenantName" Value="8c1b2d76-a666-4958-a7ec-6ef464422ad1" T="mt:wstr" /><Param Name="RoleName" Value="_b9c3354c-3275-4049-680f-3748ad0af496" T="mt:wstr" /><Param Name="RoleInstanceName" Value="8c1b2d76-a666-4958-a7ec-6ef464422ad1._b9c3354c-3275-4049-680f-3748ad0af496" T="mt:wstr" /><Param Name="ContainerId" Value="edf9b1e3-90dd-4da5-9c23-6c9a2f419ddc" T="mt:wstr" />]]></Event></Provider></TelemetryData>
    def format_data_for_wire_server
      format(TELEMETRY_XML_FORMAT, events_string: to_xml)
    end

    def length
      @event_list.length
    end

    private

    def to_xml
      # group the events by provider id
      events_grouped_by_provider = {}
      @event_list.each do |event|
        events_grouped_by_provider[event.provider_id] = [] unless events_grouped_by_provider.key?(event.provider_id)
        events_grouped_by_provider[event.provider_id] << event
      end

      xml_string_grouped_by_providers = ''
      events_grouped_by_provider.keys.each do |provider_id|
        xml_string = ''
        events_grouped_by_provider[provider_id].each do |event|
          xml_string += event.to_xml_without_provider
        end
        xml_string_grouped_by_providers += format(EVENTS_WITH_PROVIDER_FORMAT, provider_id: provider_id, event_xml_without_provider: xml_string)
      end
      xml_string_grouped_by_providers
    end
  end
end
