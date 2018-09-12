# frozen_string_literal: true

module Bosh::AzureCloud
  class AzureClient
    EPHEMERAL_DISK_LUN = 0

    private

    def _get_next_available_lun(vm_size, data_disks)
      disk_info = DiskInfo.for(vm_size)
      lun = nil
      (0..(disk_info.count - 1)).each do |i|
        disk = data_disks.find { |d| d['lun'] == i }
        if disk.nil?
          lun = i
          break
        end
      end
      lun
    end
  end
end
