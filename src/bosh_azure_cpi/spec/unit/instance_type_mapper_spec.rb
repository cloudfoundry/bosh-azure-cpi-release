# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::InstanceTypeMapper do
  subject { described_class.new }

  context 'when no possible VM sizes are found' do
    let(:desired_instance_size) do
      {
        'cpu' => 3200,
        'ram' => 102_400
      }
    end
    let(:available_vm_sizes) do
      [
        {
          name: 'Standard_A0',
          number_of_cores: 1,
          memory_in_mb: 768
        },
        {
          name: 'Standard_A1',
          number_of_cores: 1,
          memory_in_mb: 1792
        }
      ]
    end

    it 'raise an error' do
      expect do
        subject.map(desired_instance_size, available_vm_sizes)
      end.to raise_error(/Unable to meet desired instance size: 3200 CPU, 102400 MB RAM/)
    end
  end

  context 'when the closest matched VM sizes are not found' do
    let(:desired_instance_size) do
      {
        'cpu' => 1,
        'ram' => 512
      }
    end
    let(:available_vm_sizes) do
      [
        {
          name: 'Standard_NOT_EXIST_0',
          number_of_cores: 1,
          memory_in_mb: 768
        },
        {
          name: 'Standard_NOT_EXIST_1',
          number_of_cores: 1,
          memory_in_mb: 1792
        }
      ]
    end

    it 'raise an error' do
      expect do
        subject.map(desired_instance_size, available_vm_sizes)
      end.to raise_error(/Unable to find the closest matched VM sizes/)
    end
  end

  context 'when the closest matched VM sizes are found' do
    let(:desired_instance_size) do
      {
        'cpu' => 1,
        'ram' => 512
      }
    end
    let(:available_vm_sizes) do
      [
        {
          name: 'Standard_F1',
          number_of_cores: 1,
          memory_in_mb: 2048
        },
        {
          name: 'Standard_F2',
          number_of_cores: 2,
          memory_in_mb: 4096
        }
      ]
    end

    it 'return the instance type' do
      expect(subject.map(desired_instance_size, available_vm_sizes)).to eq(%w[Standard_F1 Standard_F2])
    end
  end
end
