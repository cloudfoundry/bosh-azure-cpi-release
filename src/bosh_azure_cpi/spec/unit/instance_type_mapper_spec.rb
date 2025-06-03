# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::InstanceTypeMapper do
  let(:logger) { instance_double(Logger) }
  let(:location) { 'fake-location' }
  let(:azure_client) { instance_double(Bosh::AzureCloud::AzureClient) }

  before do
    allow(Bosh::Clouds::Config).to receive(:logger).and_return(logger)
    allow(logger).to receive(:debug)
    allow(logger).to receive(:warn)
  end

  subject { described_class.new(azure_client) }

  describe '#map' do
    context 'when Azure client returns valid SKUs' do
      let(:azure_skus) do
        [
          {
            name: 'Standard_D2_v3',
            capabilities: {
              vCPUs: '2',
              MemoryGB: '8',
              PremiumIO: 'True'
            }
          },
          {
            name: 'Standard_F2',
            capabilities: {
              vCPUs: '2',
              MemoryGB: '4',
              PremiumIO: 'True'
            }
          },
          {
            name: 'Standard_A2',
            capabilities: {
              vCPUs: '2',
              MemoryGB: '3.5',
              PremiumIO: 'False'
            }
          },
          {
            name: 'Standard_D4_v3',
            capabilities: {
              vCPUs: '4',
              MemoryGB: '16',
              PremiumIO: 'True'
            }
          }
        ]
      end

      before do
        allow(azure_client).to receive(:list_vm_skus).with(location).and_return(azure_skus)
      end

      it 'returns VM sizes that meet the requirements, sorted by preference' do
        desired_instance_size = {
          'cpu' => 2,
          'ram' => 2048
        }

        result = subject.map(desired_instance_size, location)

        # Standard_A2 is included because it meets the requirements, but it's not preferred due to the lack of PremiumIO
        expect(result).to eq(['Standard_F2', 'Standard_D2_v3', 'Standard_D4_v3', 'Standard_A2'])
      end

      it 'filters out VMs that do not meet CPU requirements' do
        desired_instance_size = {
          'cpu' => 3,
          'ram' => 4096
        }

        result = subject.map(desired_instance_size, location)
        expect(result).to eq(['Standard_D4_v3'])
      end

      it 'filters out VMs that do not meet memory requirements' do
        desired_instance_size = {
          'cpu' => 2,
          'ram' => 10240
        }

        result = subject.map(desired_instance_size, location)
        expect(result).to eq(['Standard_D4_v3'])
      end

      it 'filters out non-preferred or unknown VM series' do
        azure_skus = [
          {
            name: 'Standard_D2_v3',
            capabilities: {
              vCPUs: '2',
              MemoryGB: '8',
              PremiumIO: 'True'
            }
          },
          {
            name: 'Standard_NC6',  # N series not in SERIES_PREFERENCE
            capabilities: {
              vCPUs: '6',
              MemoryGB: '56',
              PremiumIO: 'True'
            }
          },
          {
            name: 'unknown_series',  # any unknown series
            capabilities: {
              vCPUs: '1',
              MemoryGB: '1',
              PremiumIO: 'True'
            }
          },
          {
            name: 'Standard_F2',
            capabilities: {
              vCPUs: '2',
              MemoryGB: '4',
              PremiumIO: 'True'
            }
          }
        ]

        allow(azure_client).to receive(:list_vm_skus).with(location).and_return(azure_skus)

        desired_instance_size = {
          'cpu' => 1,
          'ram' => 1024
        }

        result = subject.map(desired_instance_size, location)

        expect(result).to include('Standard_D2_v3', 'Standard_F2')
        expect(result).not_to include('Standard_NC6', 'unknown_series')
      end
    end

    context 'when SKUs have invalid or missing data' do
      let(:azure_skus) do
        [
          {
            name: 'Standard_D2_v3',
            capabilities: {
              vCPUs: '2',
              MemoryGB: '8',
              PremiumIO: 'True'
            }
          },
          {
            name: 'Standard_F2',
            # Missing vCPUs or MemoryGB
            capabilities: {
              PremiumIO: 'True'
            }
          },
          {
            name: 'Standard_A2',
            # No capabilities at all
          }
        ]
      end

      before do
        allow(azure_client).to receive(:list_vm_skus).with(location).and_return(azure_skus)
      end

      it 'filters out invalid SKUs' do
        desired_instance_size = {
          'cpu' => 1,
          'ram' => 1024
        }

        result = subject.map(desired_instance_size, location)
        expect(result).to eq(['Standard_D2_v3'])
      end
    end

    context 'when SKUs have restrictions' do
      let(:azure_skus) do
        [
          {
            name: 'Standard_D2_v3',
            capabilities: {
              vCPUs: '2',
              MemoryGB: '8',
              PremiumIO: 'True'
            }
          },
          {
            name: 'Standard_F2',
            capabilities: {
              vCPUs: '2',
              MemoryGB: '4',
              PremiumIO: 'True'
            },
            restrictions: [
              {
                reasonCode: "NotAvailableForSubscription",
                type: 'Location',
                values: ['westus']
              }
            ]
          },
          {
            name: 'Standard_A2',
            capabilities: {
              vCPUs: '2',
              MemoryGB: '3.5',
              PremiumIO: 'False'
            },
            restrictions: [] # Empty restrictions array should not filter out the SKU
          }
        ]
      end

      before do
        allow(azure_client).to receive(:list_vm_skus).with(location).and_return(azure_skus)
      end

      it 'filters out SKUs with restrictions' do
        desired_instance_size = {
          'cpu' => 1,
          'ram' => 1024
        }

        result = subject.map(desired_instance_size, location)
        expect(result).to include('Standard_D2_v3', 'Standard_A2')
        expect(result).not_to include('Standard_F2')
      end
    end

    context 'when no possible VM sizes are found' do
      let(:azure_skus) do
        [
          {
            name: 'Standard_A0',
            capabilities: {
              vCPUs: '1',
              MemoryGB: '0.75',
              PremiumIO: 'False'
            }
          },
          {
            name: 'Standard_A1',
            capabilities: {
              vCPUs: '1',
              MemoryGB: '1.75',
              PremiumIO: 'False'
            }
          }
        ]
      end

      before do
        allow(azure_client).to receive(:list_vm_skus).with(location).and_return(azure_skus)
      end

      it 'raises an error' do
        desired_instance_size = {
          'cpu' => 3200,
          'ram' => 102_400
        }

        expect do
          subject.map(desired_instance_size, location)
        end.to raise_error(/Unable to meet desired instance size: 3200 CPU, 102400 MB RAM/)
      end
    end

    context 'when Azure client fails to return SKUs' do
      before do
        allow(azure_client).to receive(:list_vm_skus).with(location)
                                                          .and_raise(Bosh::AzureCloud::AzureError.new('Azure API error'))
      end

      it 'logs a warning and raises an error when no VMs match' do
        desired_instance_size = {
          'cpu' => 1,
          'ram' => 512
        }

        expect(logger).to receive(:warn).with(/Failed to fetch VM SKU information: Azure API error/)

        expect do
          subject.map(desired_instance_size, location)
        end.to raise_error(/Unable to meet desired instance size/)
      end
    end

    context 'when different VM generations are available' do
      let(:azure_skus) do
        [
          {
            name: 'Standard_D2_v2',
            capabilities: {
              vCPUs: '2',
              MemoryGB: '8',
              PremiumIO: 'True'
            }
          },
          {
            name: 'Standard_D2_v5',
            capabilities: {
              vCPUs: '2',
              MemoryGB: '8',
              PremiumIO: 'True'
            }
          },
          {
            name: 'Standard_D2_v4',
            capabilities: {
              vCPUs: '2',
              MemoryGB: '8',
              PremiumIO: 'True'
            }
          },
          {
            name: 'Standard_D2_v3',
            capabilities: {
              vCPUs: '2',
              MemoryGB: '8',
              PremiumIO: 'True'
            }
          }
        ]
      end

      before do
        allow(azure_client).to receive(:list_vm_skus).with(location).and_return(azure_skus)
      end

      it 'sorts generations based on implementation' do
        desired_instance_size = {
          'cpu' => 2,
          'ram' => 7168
        }

        result = subject.map(desired_instance_size, location)

        expect(result).to eq(['Standard_D2_v5', 'Standard_D2_v4', 'Standard_D2_v3', 'Standard_D2_v2'])
      end
    end

    context 'when different VM series are available' do
      let(:azure_skus) do
        [
          {
            name: 'Standard_E2s_v5',
            capabilities: {
              vCPUs: '2',
              MemoryGB: '4', # actually 16, but for the purpose of this test, 4, to test the sorting
              PremiumIO: 'True'
            }
          },
          {
            name: 'Standard_F2s_v2',
            capabilities: {
              vCPUs: '2',
              MemoryGB: '4',
              PremiumIO: 'True'
            }
          },
          {
            name: 'Standard_D2s_v5',
            capabilities: {
              vCPUs: '2',
              MemoryGB: '4', # actually 8, but for the purpose of this test, 4, to test the sorting
              PremiumIO: 'True'
            }
          },
          {
            name: 'Standard_F2als_v6',
            capabilities: {
              vCPUs: '2',
              MemoryGB: '4',
              PremiumIO: 'True'
            }
          }
        ]
      end

      before do
        allow(azure_client).to receive(:list_vm_skus).with(location).and_return(azure_skus)
      end

      it 'sorts based on series, then on generation' do
        desired_instance_size = {
          'cpu' => 2,
          'ram' => 4000
        }

        result = subject.map(desired_instance_size, location)

        # D series is preferred over E and F series, therefore D series should be first
        # F series and E series should be sorted based on generation, as they are equal in preference
        expect(result).to eq(['Standard_D2s_v5', 'Standard_F2als_v6', 'Standard_E2s_v5', 'Standard_F2s_v2'])
      end
    end

    context 'when SKU cache is used' do
      let(:azure_skus) do
        [
          {
            name: 'Standard_D2_v3',
            capabilities: {
              vCPUs: '2',
              MemoryGB: '8',
              PremiumIO: 'True'
            }
          }
        ]
      end

      it 'caches SKUs for the same location' do
        expect(azure_client).to receive(:list_vm_skus).with(location).once.and_return(azure_skus)

        desired_instance_size = {
          'cpu' => 1,
          'ram' => 1024
        }

        subject.map(desired_instance_size, location)
        subject.map(desired_instance_size, location)
      end

      it 'requests new SKUs for different locations' do
        location2 = 'different-location'

        expect(azure_client).to receive(:list_vm_skus).with(location).once.and_return(azure_skus)
        expect(azure_client).to receive(:list_vm_skus).with(location2).once.and_return(azure_skus)

        desired_instance_size = {
          'cpu' => 1,
          'ram' => 1024
        }

        subject.map(desired_instance_size, location)
        subject.map(desired_instance_size, location2)
      end
    end
  end
end
