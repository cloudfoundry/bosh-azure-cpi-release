# frozen_string_literal: true

module Bosh::AzureCloud
  class VHDUtils
    # Reference Virtual Hard Disk Image Format Specification
    # http://download.microsoft.com/download/f/f/e/ffef50a5-07dd-4cf8-aaa3-442c0673a029/Virtual%20Hard%20Disk%20Format%20Spec_10_18_06.doc
    def self.generate_footer(size_in_bytes)
      footer = {}
      cookie = +'conectix'
      footer[:cookie]       = cookie.force_encoding('BINARY')
      footer[:features]     = ['00000002'].pack('H*')
      footer[:ff]           = ['00010000'].pack('H*')
      footer[:offset]       = ['FFFFFFFFFFFFFFFF'].pack('H*')
      footer[:time]         = [(Time.now - Time.parse('Jan 1, 2000 12:00:00 AM GMT')).to_i.to_s(16)].pack('H*')
      rvhd = +'rvhd'
      footer[:creator_app]  = rvhd.force_encoding('UTF-8')
      footer[:creator_ver]  = ['00060002'].pack('H*')
      wi2k = +'Wi2k'
      footer[:creator_host] = wi2k.force_encoding('UTF-8')
      footer[:orig_size]    = size_in_hex(size_in_bytes)
      footer[:curr_size]    = size_in_hex(size_in_bytes)
      footer[:geometry]     = nil
      footer[:disk_type]    = ['00000002'].pack('H*')
      footer[:checksum]     = nil
      footer[:uuid]         = SecureRandom.hex.scan(/../).map { |c| c.hex.chr.force_encoding('BINARY') }.join
      footer[:state]        = ['0'].pack('H*')
      footer[:reserved]     = Array('00' * 427).pack('H*')

      footer[:geometry] = geometry(size_in_bytes)
      footer[:checksum] = checksum(footer)
      footer
    end

    def self.size_in_hex(size_in_bytes)
      hex_size = size_in_bytes.to_s(16)
      hex_size = '0' + hex_size until hex_size.length == 16
      [hex_size].pack('H*')
    end

    def self.geometry(size_in_bytes)
      max_size      = 65_535 * 16 * 255 * 512
      capacity      = size_in_bytes > max_size ? max_size : size_in_bytes
      total_sectors = capacity / 512

      if total_sectors > (65_535 * 16 * 63)
        sectors_per_track  = 255
        heads_per_cylinder = 16
      else
        sectors_per_track     = 17
        cylinders_times_heads = total_sectors / sectors_per_track
        heads_per_cylinder    = (cylinders_times_heads + 1023) / 1024
        heads_per_cylinder    = 4 if heads_per_cylinder < 4
        if cylinders_times_heads >= (heads_per_cylinder * 1024) || heads_per_cylinder > 16
          sectors_per_track  = 31
          heads_per_cylinder = 16
          cylinders_times_heads = total_sectors / sectors_per_track
        end

        if cylinders_times_heads >= heads_per_cylinder * 1024
          sectors_per_track = 63
          heads_per_cylinder = 16
        end
      end

      cylinders = (total_sectors / sectors_per_track) / heads_per_cylinder
      [cylinders, heads_per_cylinder, sectors_per_track].pack('nCC')
    end

    def self.checksum(footer)
      checksum = 0
      footer.each do |k, v|
        next if k == :checksum

        checksum += v.codepoints.inject(0) { |sum, n| sum + n }
      end
      [format('%08x', (~checksum) & 0xFFFFFFFF)].pack('H*')
    end
  end
end
