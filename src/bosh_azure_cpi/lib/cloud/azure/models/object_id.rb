# frozen_string_literal: true

module Bosh::AzureCloud
  class ObjectId
    ErrorMsg = Bosh::AzureCloud::ErrorMsg
    KEY_SEPERATOR = ';'
    attr_reader :plain_id, :id_hash

    def initialize(id_hash, plain_id = nil)
      @id_hash = id_hash
      @plain_id = plain_id
    end

    # Params:
    # - id_str: [String] the id represented in string.
    # - defaults: [Hash] the default values will use.
    def self.parse_with_defaults(id_str, defaults)
      array = id_str.split(KEY_SEPERATOR)
      id_hash = defaults
      if array.length == 1
        [id_hash, id_str]
      else
        array.each do |item|
          ret = item.match('^([^:]*):(.*)$')
          raise Bosh::Clouds::CloudError, ErrorMsg::OBJ_ID_KEY_VALUE_FORMAT_ERROR if ret.nil?

          id_hash[ret[1]] = ret[2]
        end
        [id_hash, nil]
      end
    end

    def to_s
      return @plain_id unless @plain_id.nil?

      array = []
      @id_hash.each { |key, value| array << "#{key}:#{value}" }
      array.sort.join(KEY_SEPERATOR)
    end
  end
end
