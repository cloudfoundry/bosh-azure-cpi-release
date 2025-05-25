# frozen_string_literal: true

module Bosh::AzureCloud
  class InstanceTypeMapper
    include Helpers

    SERIES_PREFERENCE = {
      'D' => 5,  # General purpose - balanced
      'F' => 4,  # Compute optimized
      'E' => 4,  # Memory optimized
      'B' => 3,  # Burstable VMs
      'L' => 3,  # Storage optimized
      'A' => 2,  # Basic general purpose
      'H' => 1,  # High performance compute
      'M' => 1,  # Ultra memory optimized
      'N' => 1   # GPU
    }.freeze

    def initialize(azure_client)
      @azure_client = azure_client
      @logger = Bosh::Clouds::Config.logger
      @sku_cache = {}
    end

    def map(desired_instance_size, location)
      @logger.debug("Finding VM size with minimum #{desired_instance_size['cpu']} CPU, #{desired_instance_size['ram']} MB RAM")

      prepared_skus = get_vm_skus(location).map do |sku|
        has_restrictions = sku.key?(:restrictions) && !sku[:restrictions].empty?
        has_required_capabilities = sku.key?(:capabilities) &&
                                    sku[:capabilities].key?(:vCPUs) &&
                                    sku[:capabilities].key?(:MemoryGB)

        next nil unless has_required_capabilities && !has_restrictions

        {
          original_sku: sku,
          name: sku[:name],
          cores: sku[:capabilities][:vCPUs].to_i,
          memory_mb: (sku[:capabilities][:MemoryGB].to_f * 1024).to_i,
          premium_io: sku[:capabilities][:PremiumIO] == 'True' ? 1 : 0,
          generation: extract_generation(sku[:name]),
          series_score: get_series_score(sku[:name])
        }
      end.compact

      possible_vm_sizes = prepared_skus.select do |sku|
        sku[:cores] >= desired_instance_size['cpu'] &&
        sku[:memory_mb] >= desired_instance_size['ram']
      end

      cloud_error("Unable to meet desired instance size: #{desired_instance_size['cpu']} CPU, #{desired_instance_size['ram']} MB RAM") if possible_vm_sizes.empty?

      closest_matched_vm_sizes = possible_vm_sizes.sort_by do |sku|
        [-sku[:premium_io], sku[:cores], sku[:memory_mb], -sku[:series_score], -sku[:generation]]
      end.map { |sku| sku[:name] }

      @logger.debug("Selected VM sizes (in order): #{closest_matched_vm_sizes.join(', ')}")
      closest_matched_vm_sizes
    end

    private

    def get_vm_skus(location)
      cache_key = "skus-#{location}"
      unless @sku_cache[cache_key]
        begin
          @logger.debug("Fetching VM SKU information for location: #{location}")
          @sku_cache[cache_key] = @azure_client.list_vm_skus(location)
        rescue => e
          @logger.warn("Failed to fetch VM SKU information: #{e.message}")
          return []
        end
      end

      @sku_cache[cache_key]
    end

    def extract_generation(vm_name)
      match = vm_name.downcase.match(/_v(\d+)/)
      match ? match[1].to_i : 1 # Default to gen 1 for non-versioned VMs
    end

    def get_series_score(vm_name)
      SERIES_PREFERENCE.each do |series, score|
        return score if vm_name.downcase.match(/standard_#{series}\d/i)
      end
      0 # Default score for unknown series
    end
  end
end
