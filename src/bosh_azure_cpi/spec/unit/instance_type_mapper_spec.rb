require 'spec_helper'

describe Bosh::AzureCloud::InstanceTypeMapper do
  subject { described_class.new }

  context "when no possible VM sizes are found" do
    let(:vm_resources) {
      {
        'cpu' => 3200,
        'ram' => 102400,
      }
    }
    let(:available_vm_sizes) {
      [
        {
          :name => "Standard_A0",
          :number_of_cores => 1,
          :memory_in_mb => 768
        },
        {
          :name => "Standard_A1",
          :number_of_cores => 1,
          :memory_in_mb => 1792
        }
      ]
    }

    it 'raise an error' do
      expect {
        subject.map(vm_resources, available_vm_sizes)
      }.to raise_error(/Unable to meet requested vm_resources: 3200 CPU, 102400 MB RAM/)
    end
  end

  context "when the closest matched VM sizes are not found" do
    let(:vm_resources) {
      {
        'cpu' => 1,
        'ram' => 512
      }
    }
    let(:available_vm_sizes) {
      [
        {
          :name => "Standard_NOT_EXIST_0",
          :number_of_cores => 1,
          :memory_in_mb => 768
        },
        {
          :name => "Standard_NOT_EXIST_1",
          :number_of_cores => 1,
          :memory_in_mb => 1792
        }
      ]
    }

    it 'raise an error' do
      expect {
        subject.map(vm_resources, available_vm_sizes)
      }.to raise_error(/Unable to find the closest matched VM sizes/)
    end
  end

  context "when the closest matched VM sizes are found" do
    let(:vm_resources) {
      {
        'cpu' => 1,
        'ram' => 512,
      }
    }
    let(:available_vm_sizes) {
      [
        {
          :name => "Standard_F1",
          :number_of_cores => 1,
          :memory_in_mb => 2048
        },
        {
          :name => "Standard_F2",
          :number_of_cores => 2,
          :memory_in_mb => 4096
        }
      ]
    }

    it 'return the instance type' do
      expect(subject.map(vm_resources, available_vm_sizes)).to eq("Standard_F1")
    end
  end
end
