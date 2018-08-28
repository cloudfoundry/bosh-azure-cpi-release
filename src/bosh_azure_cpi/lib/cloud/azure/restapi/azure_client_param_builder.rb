# frozen_string_literal: true

module Bosh::AzureCloud
  class AzureClient
    private

    def _build_os_profile(vm_params)
      os_profile = {
        'customData'         => vm_params[:custom_data],
        'computerName'       => vm_params[:computer_name].nil? ? vm_params[:name] : vm_params[:computer_name]
      }

      case vm_params[:os_type]
      when 'linux'
        os_profile['adminUsername'] = vm_params[:ssh_username]
        os_profile['linuxConfiguration'] = {
          'disablePasswordAuthentication' => 'true',
          'ssh' => {
            'publicKeys' => [
              {
                'path'    => "/home/#{vm_params[:ssh_username]}/.ssh/authorized_keys",
                'keyData' => vm_params[:ssh_cert_data]
              }
            ]
          }
        }
      when 'windows'
        os_profile['adminUsername'] = vm_params[:windows_username]
        os_profile['adminPassword'] = vm_params[:windows_password]
        os_profile['windowsConfiguration'] = {
          'enableAutomaticUpdates' => false
        }
      else
        raise ArgumentError, "Unsupported os type: #{vm_params[:os_type]}"
      end
      os_profile
    end
  end
end
