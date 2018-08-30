# frozen_string_literal: true

module Bosh::AzureCloud
  class InstanceTypeMapper
    include Helpers

    # https://docs.microsoft.com/en-us/azure/virtual-machines/linux/sizes
    # The below array defines different series. The former series is recommended than the latter.
    # 1. VM sizes which supports Premium storage are recommended;
    # 2. New generations are recommended: v3 > v2 > v1 > previous generations;
    # 3. General purpose (Balanced CPU-to-memory ratio) > Compute optimized (High CPU-to-memory ratio) > Memory optimized (High memory-to-CPU ratio);
    # 4. High performance compute is listed at the end;
    # 4. The following sizes are not recommended:
    #      a. The sizes with GPU (NV, NC, ND);
    #      b. The M-series which has lots of CPUs and memories.
    #      c. The Basic tier sizes (they don't support load balancing);
    RECOMMENDED_VM_SIZES = [
      # Premium Storage
      %w[Standard_D2s_v3 Standard_D4s_v3 Standard_D8s_v3 Standard_D16s_v3 Standard_D32s_v3 Standard_D64s_v3],
      %w[Standard_E2s_v3 Standard_E4s_v3 Standard_E8s_v3 Standard_E16s_v3 Standard_E32s_v3 Standard_E64s_v3 Standard_E64is_v3],
      %w[Standard_DS1_v2 Standard_DS2_v2 Standard_DS3_v2 Standard_DS4_v2 Standard_DS5_v2],
      %w[Standard_F2s_v2 Standard_F4s_v2 Standard_F8s_v2 Standard_F16s_v2 Standard_F32s_v2 Standard_F64s_v2 Standard_F72s_v2],
      %w[Standard_DS11_v2 Standard_DS12_v2 Standard_DS13_v2 Standard_DS14_v2 Standard_DS15_v2],
      %w[Standard_B1s Standard_B1ms Standard_B2s Standard_B2ms Standard_B4ms Standard_B8ms],
      %w[Standard_F1s Standard_F2s Standard_F4s Standard_F8s Standard_F16s],
      %w[Standard_GS1 Standard_GS2 Standard_GS3 Standard_GS4 Standard_GS5],
      %w[Standard_DS1 Standard_DS2 Standard_DS3 Standard_DS4 Standard_DS11 Standard_DS12 Standard_DS13 Standard_DS14],
      # Standard Storage
      %w[Standard_D2_v3 Standard_D4_v3 Standard_D8_v3 Standard_D16_v3 Standard_D32_v3 Standard_D64_v3],
      %w[Standard_E2_v3 Standard_E4_v3 Standard_E8_v3 Standard_E16_v3 Standard_E32_v3 Standard_E64_v3 Standard_E64i_v3],
      %w[Standard_D1_v2 Standard_D2_v2 Standard_D3_v2 Standard_D4_v2 Standard_D5_v2],
      %w[Standard_A1_v2 Standard_A2_v2 Standard_A4_v2 Standard_A8_v2 Standard_A2m_v2 Standard_A4m_v2 Standard_A8m_v2],
      %w[Standard_D11_v2 Standard_D12_v2 Standard_D13_v2 Standard_D14_v2 Standard_D15_v2],
      %w[Standard_F1 Standard_F2 Standard_F4 Standard_F8 Standard_F16],
      %w[Standard_G1 Standard_G2 Standard_G3 Standard_G4 Standard_G5],
      %w[Standard_D1 Standard_D2 Standard_D3 Standard_D4 Standard_D11 Standard_D12 Standard_D13 Standard_D14],
      %w[Standard_A1 Standard_A2 Standard_A3 Standard_A4 Standard_A5 Standard_A6 Standard_A7 Standard_A8 Standard_A9 Standard_A10 Standard_A11],
      # High performance compute
      %w[Standard_H8 Standard_H16 Standard_H8m Standard_H16m Standard_H16r Standard_H16mr]
    ].freeze

    def map(desired_instance_size, available_vm_sizes)
      @logger = Bosh::Clouds::Config.logger
      @logger.debug("The available VM sizes in the specified region are '#{_vm_sizes_to_string(available_vm_sizes)}'")
      possible_vm_sizes = _find_possible_vm_sizes(desired_instance_size, available_vm_sizes)
      cloud_error("Unable to meet desired instance size: #{desired_instance_size['cpu']} CPU, #{desired_instance_size['ram']} MB RAM") if possible_vm_sizes.empty?
      @logger.debug("The possible VM sizes which meet desired instance size are '#{_vm_sizes_to_string(possible_vm_sizes)}'")

      closest_matched_vm_sizes = _find_closest_matched_vm_sizes(possible_vm_sizes)
      @logger.debug("The closest matched VM sizes are '#{closest_matched_vm_sizes}'")

      closest_matched_vm_sizes
    end

    private

    def _find_possible_vm_sizes(desired_instance_size, available_vm_sizes)
      available_vm_sizes.select do |vm_size|
        vm_size[:number_of_cores] >= desired_instance_size['cpu'] &&
          vm_size[:memory_in_mb] >= desired_instance_size['ram']
      end
    end

    def _find_closest_matched_vm_sizes(possible_vm_sizes)
      vm_sizes = possible_vm_sizes.reject do |vm_size|
        _find_index(vm_size) == -1
      end
      cloud_error('Unable to find the closest matched VM sizes') if vm_sizes.empty?
      @logger.debug("The recommended VM sizes are '#{_vm_sizes_to_string(vm_sizes)}'")

      vm_sizes = vm_sizes.sort_by do |vm_size|
        support_premium_storage = support_premium_storage?(vm_size[:name]) ? 0 : 1
        priority = _find_index(vm_size)
        [support_premium_storage, vm_size[:number_of_cores], vm_size[:memory_in_mb], priority]
      end
      cloud_error('Unable to find the closest matched VM sizes') if vm_sizes.empty?
      @logger.debug("The sorted VM sizes are '#{_vm_sizes_to_string(vm_sizes)}'")

      closest_matched_vm_sizes = []
      vm_sizes.each do |vm_size|
        closest_matched_vm_sizes.push(vm_size[:name])
      end
      closest_matched_vm_sizes
    end

    def _find_index(vm_size)
      RECOMMENDED_VM_SIZES.each_index do |index|
        return index if RECOMMENDED_VM_SIZES[index].map(&:downcase).include?(vm_size[:name].downcase)
      end
      -1
    end

    def _vm_sizes_to_string(vm_sizes)
      vm_sizes = vm_sizes.map { |vm_size| "#{vm_size[:name]}: #{vm_size[:number_of_cores]} CPU, #{vm_size[:memory_in_mb]} MB RAM" }
      vm_sizes.join(';')
    end
  end
end
