require 'azure'
require_relative 'helpers'

module Bosh::AzureCloud
  class ReservedIpManager

    include Helpers

    def exist?(ip)
      !find(ip).nil?
    end

    def create(name)
      handle_response post("https://management.core.windows.net/#{Azure.config.subscription_id}"  \
                           '/services/networking/reservedips', "<?xml version=\"1.0\" encoding=\"utf-8\"?>"  \
                                                               "<ReservedIP xmlns=\"http://schemas.microsoft.com/windowsazure\">"  \
                                                               "<Name>#{name}</Name>"  \
                                                               '<Location>East US</Location>'  \
                                                               '</ReservedIP>')

      find("https://management.core.windows.net/#{Azure.config.subscription_id}"  \
           "/services/networking/reservedips/#{name}")['Address']
    end

    def in_use?(ip)
      find(ip)['InUse']
    end

    def find(ip)
      handle_response find("https://management.core.windows.net/#{Azure.config.subscription_id}"  \
                          '/services/networking/reservedips')['ReservedIP'].select { |_ip| _ip['Address'] == ip }
    end
  end
end