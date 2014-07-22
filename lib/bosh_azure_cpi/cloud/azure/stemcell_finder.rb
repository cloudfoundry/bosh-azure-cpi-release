require_relative 'stemcell'

module Bosh::AzureCloud
  class StemcellFinder

    def initialize(client)
      @client = client
    end

    def find_stemcell_by_name(name)
      stemcell = @client.list_virtual_machine_images.find do |image|
        image.name == name
      end

      raise Bosh::Clouds::CloudError, "Given image name '#{name}' does not exist!" if stemcell.nil?
      stemcell
    end
  end
end