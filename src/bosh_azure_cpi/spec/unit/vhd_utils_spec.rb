# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::VHDUtils do
  context 'when big vhd' do
    it 'should succees' do
      footer = nil
      expect do
        footer = Bosh::AzureCloud::VHDUtils.generate_footer(1024 * 1024 * 1024 * 1024)
      end.not_to raise_error
      expect(footer[:geometry]).to eq([655_35, 16, 255].pack('nCC'))
    end
  end

  context 'when small vhd' do
    it 'should succees' do
      footer = nil
      expect do
        footer = Bosh::AzureCloud::VHDUtils.generate_footer((65_535 * 16 * 63 * 512) - 512)
      end.not_to raise_error
      expect(footer[:geometry]).to eq([655_34, 16, 63].pack('nCC'))
    end
  end
end
