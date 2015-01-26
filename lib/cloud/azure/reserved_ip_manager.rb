module Bosh::AzureCloud
  class ReservedIpManager
    RESERVED_IP_LABEL = 'bosh'
    
    attr_accessor :logger

    include Helpers

    def initialize
      @logger = Bosh::Clouds::Config.logger
    end

    def exist?(ip)
      !find(ip).nil?
    end

    def create(name, location)
      handle_response http_post('/services/networking/reservedips', 
                           "<?xml version=\"1.0\" encoding=\"utf-8\"?>"  \
                           "<ReservedIP xmlns=\"http://schemas.microsoft.com/windowsazure\">"  \
                           "<Name>#{name}</Name>"  \
                           "<Label>#{RESERVED_IP_LABEL}</Label>"  \
                           "<Location>#{location}</Location>"  \
                           '</ReservedIP>')

      find_ip_by_name(name)
    rescue => e
      cloud_error("Failed to create reserved_ip: #{e.message}\n#{e.backtrace.join("\n")}")
    end
    
    def find_ip_by_name(name)
      logger.info("Finding reserved ip by name #{name}")
      reserved_ip = {}
      response = handle_response http_get("/services/networking/reservedips/#{name}")
      
      ip = response.css('ReservedIP')
      reserved_ip[:name] = xml_content(ip, 'Name')
      reserved_ip[:address] = xml_content(ip, 'Address')
      reserved_ip[:id] = xml_content(ip, 'Id')
      reserved_ip[:label] = xml_content(ip, 'Label')
      reserved_ip[:state] = xml_content(ip, 'State')
      reserved_ip[:in_use] = (xml_content(ip, 'InUse').downcase == 'true')
      reserved_ip[:service_name] = xml_content(ip, 'ServiceName')
      reserved_ip[:deployment_name] = xml_content(ip, 'DeploymentName')
      reserved_ip[:location] = xml_content(ip, 'Location')
      reserved_ip
    rescue => e
      cloud_error("Failed to find reserved_ip by name #{name}: #{e.message}\n#{e.backtrace.join("\n")}")
    end

    def find(ip)
      logger.info("Finding reserved ip by address #{ip}")
      response = handle_response http_get("/services/networking/reservedips")

      reserved_ip = nil
      response.css('ReservedIPs ReservedIP').each do |i|
        ip_address = xml_content(i, 'Address')
        name = xml_content(i, 'Name')
        
        logger.debug("name: #{name} - #{ip_address}")
        
        if ip_address == ip
          reserved_ip = {}
          reserved_ip[:name] = name
          reserved_ip[:address] = ip_address
          reserved_ip[:id] = xml_content(i, 'Id')
          reserved_ip[:label] = xml_content(i, 'Label')
          reserved_ip[:state] = xml_content(i, 'State')
          reserved_ip[:in_use] = (xml_content(i, 'InUse').downcase == 'true')
          reserved_ip[:service_name] = xml_content(i, 'ServiceName')
          reserved_ip[:deployment_name] = xml_content(i, 'DeploymentName')
          reserved_ip[:location] = xml_content(i, 'Location')
          break 
        end
      end
      reserved_ip
    rescue => e
      cloud_error("Failed to find reserved_ip by ip #{ip}: #{e.message}\n#{e.backtrace.join("\n")}")
    end
  end
end