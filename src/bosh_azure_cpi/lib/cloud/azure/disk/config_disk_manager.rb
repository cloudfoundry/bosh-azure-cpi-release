# frozen_string_literal: true

module Bosh::AzureCloud
  class ConfigDiskManager
    include Helpers

    BOSH_CONFIG_DISK_LABEL = 'azure_cfg_dsk'
    CONFIG_DISK_CONTAINER  = 'azure-config-disks'
    CONFIG_DISK_MOUNT_POINT = 'azure_config_disk_mount'
    CONFIG_DISK_FILE_PATH_PREFIX = 'azure_config_disk_image'
    CONFIGS_RELATIVE_PATH = 'configs'
    CONFIG_DISK_SIZE = 24 # in MB, azure have a requirement for the min size.
    MEGA_SIZE = 1024 * 1024
    def initialize(blob_manager, disk_manager2, storage_account_manager)
      @blob_manager = blob_manager
      @disk_manager2 = disk_manager2
      @storage_account_manager = storage_account_manager
      @logger = Bosh::Clouds::Config.logger
    end

    # Returns the config disk uri.
    def prepare_config_disk(resource_group_name, vm_name, location, meta_data_obj, user_data_obj)
      @logger.info("prepare_config_disk(#{resource_group_name},#{vm_name},#{location},...,...)")
      mounted_dir = nil
      config_disk_file_path = nil
      disk_name = nil
      page_blob_created = false
      command_runner = CommandRunner.new
      umounted = false
      begin
        config_disk_file = Tempfile.new(CONFIG_DISK_FILE_PATH_PREFIX)
        config_disk_file.close
        config_disk_file_path = config_disk_file.path

        mk_image_file_cmd = "dd if=/dev/zero of=#{config_disk_file_path} bs=#{MEGA_SIZE} count=#{CONFIG_DISK_SIZE}"
        command_runner.run_command(mk_image_file_cmd)

        mkfs_cmd = "mkfs.ext4 -F #{config_disk_file_path} -L #{BOSH_CONFIG_DISK_LABEL}"
        command_runner.run_command(mkfs_cmd)

        mounted_dir = Dir.mktmpdir("#{CONFIG_DISK_MOUNT_POINT}#{SecureRandom.uuid}")

        mount_cmd = "sudo -n mount -o loop #{config_disk_file_path} #{mounted_dir}"
        command_runner.run_command(mount_cmd)

        user = Etc.getpwuid(Process.uid).name
        chmod_cmd = "sudo -n chown #{user} #{mounted_dir}"
        command_runner.run_command(chmod_cmd)

        mkdir_cmd = "mkdir -p #{mounted_dir}/#{CONFIGS_RELATIVE_PATH}"
        command_runner.run_command(mkdir_cmd)

        meta_data_str = JSON.dump(meta_data_obj)
        File.open("#{mounted_dir}/#{CONFIGS_RELATIVE_PATH}/MetaData", 'w') do |file|
          file.write(meta_data_str)
        end

        user_data_str = JSON.dump(user_data_obj)
        File.open("#{mounted_dir}/#{CONFIGS_RELATIVE_PATH}/UserData", 'w') do |file|
          file.write(user_data_str)
        end

        unmount_cmd = "sudo -n umount #{mounted_dir}"
        command_runner.run_command(unmount_cmd)
        umounted = true

        disk_name = "#{MANAGED_CONFIG_DISK_PREFIX}-#{vm_name}.vhd"
        @blob_manager.create_vhd_page_blob(
          @storage_account_manager.default_storage_account_name,
          CONFIG_DISK_CONTAINER,
          config_disk_file_path,
          disk_name,
          {}
        )
        page_blob_created = true
        config_disk_file_uri = @blob_manager.get_blob_uri(@storage_account_manager.default_storage_account_name, CONFIG_DISK_CONTAINER, disk_name)
        disk_id = DiskId.create('None', true, disk_name: disk_name, resource_group_name: resource_group_name)

        @disk_manager2.create_disk_from_blob(disk_id, config_disk_file_uri, location, STORAGE_ACCOUNT_TYPE_STANDARD_LRS)

        disk = @disk_manager2.get_data_disk(disk_id)
        @logger.info("disk created: #{disk}")
        # TODO: defer one task to clean up the config disk.
        #       we need to acquire the lock for the resources we are operating too.
        [disk_id, disk]
      rescue StandardError => e
        cloud_error("Failed to prepare the config disk, Error: #{e.inspect}\n#{e.backtrace.join("\n")}")
      ensure
        # clean up. do not delete the blob
        ignore_exception do
          unless umounted
            unmount_cmd = "sudo -n umount #{mounted_dir}"
            command_runner.run_command(unmount_cmd)
          end
        end
        ignore_exception { FileUtils.remove_dir(mounted_dir) unless mounted_dir.nil? }
        ignore_exception { FileUtils.rm(config_disk_file_path) unless config_disk_file_path.nil? }
        ignore_exception do
          @blob_manager.delete_blob(@storage_account_manager.default_storage_account_name, CONFIG_DISK_CONTAINER, disk_name) if page_blob_created
        end
      end
    end
  end
end
