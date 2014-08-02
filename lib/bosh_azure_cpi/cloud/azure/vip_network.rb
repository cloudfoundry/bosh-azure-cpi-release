require_relative 'network'

module Bosh::AzureCloud
  class VipNetwork < Network
    attr_accessor :tcp_endpoints

    def initialize(vnet_client, spec)
      super(vnet_client, spec)

      @tcp_endpoints = parse_endpoints(spec['tcp_endpoints']) || []
    end

    # TODO: Need to research how to assigne a user-provided public IP (AWS EIP equivalent)
    def provision
      # Nothing to provision... Public ip is already auto-assigned by azure
      nil
    end

    private

    def parse_endpoints(endpoints)
      return nil if (endpoints.nil?)
      raise ArgumentError, "Invalid 'tcp_endpoints', Array expected, " \
                           "#{spec.class} provided" unless endpoints.is_a?(Array)

      endpoint_list = []
      endpoints.each do |endpoint|
        raise "Invalid tcp endpoint '#{endpoint}' given. Format is 'X:Y' where 'X' " \
              "is an internal-facing port between 1 and 65535 and 'Y' is an external-facing " \
              'port in the same range' if !valid_endpoint?(endpoint)
        endpoint_list << endpoint
      end

      return endpoint_list
    end

    def valid_endpoint?(endpoint)
      return false if (endpoint !~ /^\d+:\d+$/)
      endpoint.split(':').each do |port|
        return false if (port.to_i < 0 || port.to_i > 65535)
      end
    end
  end
end