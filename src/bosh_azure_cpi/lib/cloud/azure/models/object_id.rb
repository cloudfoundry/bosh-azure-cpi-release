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
    # - properties: [String] the properties.
    def self.create(properties)
      @properties = properties
    end

    # Params:
    # - id_str: [String] the id represented in string.
    # - defaults: [Hash] the default values will use.
    def self.parse(id_str, defaults)
      array = id_str.split(KEY_SEPERATOR)
      id_hash = {}
      obj_id = nil
      if array.length == 1
        obj_id = ObjectId.new(defaults, id_str)
      else
        array.each do |item|
          ret = item.match('^([^:]*):(.*)$')
          if ret.nil?
            cloud_error(ErrorMsg::OBJ_ID_KEY_VALUE_FORMAT_ERROR)
          else
            id_hash[ret[1]] = ret[2]
          end
        end
        obj_id = ObjectId.new(id_hash.merge(defaults))
      end

      obj_id
    end

    def to_s
      return @plain_id unless @plain_id.nil?
      array = []
      @id_hash.each { |key, value| array << "#{key}:#{value}" }
      array.sort.join(KEY_SEPERATOR)
    end
  end
end
